# =============================================================================
# modules/github-wif/main.tf
#
# Workload Identity Federation (WIF) for GitHub Actions.
#
# WIF allows GitHub Actions to authenticate to GCP using OIDC tokens issued
# by GitHub — no JSON service account keys needed.
#
# FLOW:
# ─────────────────────────────────────────────────────────────────────────────
#   GitHub Actions job starts
#    │  (requests OIDC token from GitHub)
#    ▼
#   GitHub OIDC Provider  (https://token.actions.githubusercontent.com)
#    │  (issues JWT with: repository, workflow, actor, ref claims)
#    ▼
#   GCP WIF Pool  (validates JWT against GitHub's JWKS endpoint)
#    │  (maps JWT claims to Google identity attributes)
#    ▼
#   Attribute Condition  (restricts to specific repository only)
#    │  (assertion.repository == 'owner/repo')
#    ▼
#   sa-github-actions GCP SA  (impersonated via IAM binding)
#    │  (has: AR writer, GKE developer, token creator roles from Phase 2)
#    ▼
#   GCP APIs  (Artifact Registry push, GKE get-credentials)
# =============================================================================

# =============================================================================
# WHY GCLOUD-DRIVEN INSTEAD OF TERRAFORM-MANAGED RESOURCES?
# =============================================================================
# GCP does NOT truly delete WIF pools or providers. Calling the delete API
# (which terraform destroy does) puts them into a DELETED soft-delete state
# for 30 days. They CANNOT be hard-deleted.
#
# Problem with Terraform-managed resources (the old approach):
#   1. terraform destroy → GCP soft-deletes the pool
#   2. terraform apply  → Terraform sees pool not in state → tries CREATE
#   3. GCP returns Error 409: "Requested entity already exists"
#   4. The restore null_resource helps detect DELETED state but Terraform
#      still calls the CREATE API after the restore → same 409 error
#
# Fix: Manage pool+provider entirely via gcloud commands (fully idempotent).
# Read them back via data sources so downstream resources get the right names.
# This works correctly on every destroy/apply cycle with zero errors.
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# WIF Pool — idempotent gcloud management
#
# Logic:
#   ACTIVE    → already good, do nothing
#   DELETED   → undelete (restore from soft-delete) and wait for propagation
#   NOT_FOUND → create fresh
# ─────────────────────────────────────────────────────────────────────────────
resource "null_resource" "wif_pool" {
  triggers = {
    # Always run so the pool is guaranteed to exist after every apply.
    # Using a timestamp would re-run on every plan; using static values
    # means it runs once per state entry lifetime (correct for our use case).
    pool_id    = "github-pool"
    project_id = var.project_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      POOL_STATE=$(gcloud iam workload-identity-pools describe github-pool \
        --location=global \
        --project=${var.project_id} \
        --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

      echo "WIF pool state: [$POOL_STATE]"

      if [ "$POOL_STATE" = "ACTIVE" ]; then
        echo "Pool is already ACTIVE — nothing to do."

      elif [ "$POOL_STATE" = "DELETED" ]; then
        echo "Pool is soft-deleted — undeleting..."
        gcloud iam workload-identity-pools undelete github-pool \
          --location=global \
          --project=${var.project_id}
        echo "Waiting 15s for undelete to propagate..."
        sleep 15
        echo "Pool restored successfully."

      else
        echo "Pool not found — creating..."
        gcloud iam workload-identity-pools create github-pool \
          --location=global \
          --project=${var.project_id} \
          --display-name="GitHub Actions Pool" \
          --description="Workload Identity Pool for GitHub Actions CI/CD"
        echo "Waiting 10s for pool to be ready..."
        sleep 10
        echo "Pool created successfully."
      fi
    EOT
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# WIF Provider — idempotent gcloud management
#
# Same logic as the pool: detect state, then create/undelete/skip.
# Always runs after the pool is guaranteed to be ACTIVE.
# ─────────────────────────────────────────────────────────────────────────────
resource "null_resource" "wif_provider" {
  triggers = {
    pool_id     = "github-pool"
    provider_id = "github-provider"
    project_id  = var.project_id
    github_repo = var.github_repo
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      PROVIDER_STATE=$(gcloud iam workload-identity-pools providers describe github-provider \
        --workload-identity-pool=github-pool \
        --location=global \
        --project=${var.project_id} \
        --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

      echo "WIF provider state: [$PROVIDER_STATE]"

      if [ "$PROVIDER_STATE" = "ACTIVE" ]; then
        echo "Provider is already ACTIVE — nothing to do."

      elif [ "$PROVIDER_STATE" = "DELETED" ]; then
        echo "Provider is soft-deleted — undeleting..."
        gcloud iam workload-identity-pools providers undelete github-provider \
          --workload-identity-pool=github-pool \
          --location=global \
          --project=${var.project_id}
        echo "Waiting 15s for undelete to propagate..."
        sleep 15
        echo "Provider restored successfully."

      else
        echo "Provider not found — creating..."
        gcloud iam workload-identity-pools providers create-oidc github-provider \
          --workload-identity-pool=github-pool \
          --location=global \
          --project=${var.project_id} \
          --display-name="GitHub OIDC Provider" \
          --description="OIDC provider for GitHub Actions" \
          --issuer-uri="https://token.actions.githubusercontent.com" \
          --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.workflow=assertion.workflow,attribute.ref=assertion.ref" \
          --attribute-condition="assertion.repository == '${var.github_repo}'"
        echo "Waiting 10s for provider to be ready..."
        sleep 10
        echo "Provider created successfully."
      fi
    EOT
  }

  depends_on = [null_resource.wif_pool]
}

# ─────────────────────────────────────────────────────────────────────────────
# Data sources — read the pool and provider that now definitely exist
# Used by outputs and IAM binding below.
# ─────────────────────────────────────────────────────────────────────────────
data "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  project                   = var.project_id

  depends_on = [null_resource.wif_pool]
}

data "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = "github-pool"
  workload_identity_pool_provider_id = "github-provider"
  project                            = var.project_id

  depends_on = [null_resource.wif_provider]
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM Binding — WIF Principal → sa-github-actions
# Allows the GitHub Actions pool to impersonate the sa-github-actions SA.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.github_actions_sa_email}"
  role               = "roles/iam.workloadIdentityUser"

  member = "principalSet://iam.googleapis.com/${data.google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"

  depends_on = [null_resource.wif_provider]
}
