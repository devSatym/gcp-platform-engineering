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
# WHY THIS USES GCLOUD NULL_RESOURCE INSTEAD OF TERRAFORM RESOURCES
# =============================================================================
# GCP does NOT hard-delete WIF pools/providers. terraform destroy calls the
# delete API → GCP soft-deletes for 30 days. Next terraform apply sees them
# not in state → tries CREATE → Error 409 (entity already exists).
#
# The previous approach (null_resource restore + google_iam_workload_identity_pool
# resource) failed because:
#   1. null_resource undeletes pool (ACTIVE again)
#   2. google_iam_workload_identity_pool calls CREATE anyway (not in state)
#   3. GCP returns 409
#
# Fix: Manage pool/provider ENTIRELY via gcloud (create/undelete/noop).
# Never use a Terraform-managed resource for them — no resource = no 409.
# Compute pool/provider resource names from known GCP naming patterns.
# data.google_project gives us the numeric project ID for the name.
# =============================================================================

# Get numeric project ID — needed to build the WIF resource name strings.
# Format: projects/{NUMBER}/locations/global/workloadIdentityPools/{pool_id}
data "google_project" "project" {
  project_id = var.project_id
}

locals {
  wif_pool_name     = "projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/github-pool"
  wif_provider_name = "${local.wif_pool_name}/providers/github-provider"
}

# ─────────────────────────────────────────────────────────────────────────────
# WIF Pool — fully idempotent via gcloud
# Runs on every apply. Handles all 3 states: ACTIVE (noop), DELETED (undelete),
# NOT_FOUND (create). No Terraform resource → no 409 ever.
# ─────────────────────────────────────────────────────────────────────────────
resource "null_resource" "wif_pool" {
  triggers = {
    pool_id    = "github-pool"
    project_id = var.project_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      POOL_STATE=$(gcloud iam workload-identity-pools describe github-pool \
        --location=global \
        --project=${var.project_id} \
        --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

      echo "WIF pool state: $POOL_STATE"

      if [ "$POOL_STATE" = "ACTIVE" ]; then
        echo "Pool already ACTIVE — nothing to do."
      elif [ "$POOL_STATE" = "DELETED" ]; then
        echo "Pool soft-deleted — undeleting..."
        gcloud iam workload-identity-pools undelete github-pool \
          --location=global --project=${var.project_id}
        sleep 15
        echo "Pool restored."
      else
        echo "Pool not found — creating..."
        gcloud iam workload-identity-pools create github-pool \
          --location=global \
          --project=${var.project_id} \
          --display-name="GitHub Actions Pool"
        sleep 10
        echo "Pool created."
      fi
    EOT
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# WIF Provider — fully idempotent via gcloud
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
      PROVIDER_STATE=$(gcloud iam workload-identity-pools providers describe github-provider \
        --workload-identity-pool=github-pool \
        --location=global \
        --project=${var.project_id} \
        --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

      echo "WIF provider state: $PROVIDER_STATE"

      if [ "$PROVIDER_STATE" = "ACTIVE" ]; then
        echo "Provider already ACTIVE — nothing to do."
      elif [ "$PROVIDER_STATE" = "DELETED" ]; then
        echo "Provider soft-deleted — undeleting..."
        gcloud iam workload-identity-pools providers undelete github-provider \
          --workload-identity-pool=github-pool \
          --location=global --project=${var.project_id}
        sleep 15
        echo "Provider restored."
      else
        echo "Provider not found — creating..."
        gcloud iam workload-identity-pools providers create-oidc github-provider \
          --workload-identity-pool=github-pool \
          --location=global \
          --project=${var.project_id} \
          --display-name="GitHub OIDC Provider" \
          --issuer-uri="https://token.actions.githubusercontent.com" \
          --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.workflow=assertion.workflow,attribute.ref=assertion.ref" \
          --attribute-condition="assertion.repository == '${var.github_repo}'"
        sleep 10
        echo "Provider created."
      fi
    EOT
  }

  depends_on = [null_resource.wif_pool]
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM Binding — WIF Principal → sa-github-actions
# Uses the computed pool name (from project number) — no resource reference needed.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.github_actions_sa_email}"
  role               = "roles/iam.workloadIdentityUser"

  member = "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repository/${var.github_repo}"

  depends_on = [null_resource.wif_provider]
}

