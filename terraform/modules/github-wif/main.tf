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

# ─────────────────────────────────────────────────────────────────────────────
# Workload Identity Pool
# The pool is a container for all external identity providers.
# One pool can have multiple providers (e.g., GitHub, CircleCI, GitLab).
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# PRE-CREATE LIFECYCLE: Handle GCP WIF soft-delete (30-day hold)
#
# GCP does NOT support hard deletion of WIF pools/providers. When Terraform
# destroys them, GCP soft-deletes them for 30 days. If you try to create a
# pool/provider with the same ID within 30 days, GCP returns Error 409.
#
# This null_resource runs BEFORE the WIF pool is created and automatically
# undeletes it if it's in DELETED state — making destroy/apply cycles clean.
# ─────────────────────────────────────────────────────────────────────────────
resource "null_resource" "wif_pool_restore" {
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

      if [ "$POOL_STATE" = "DELETED" ]; then
        echo "Pool is soft-deleted — undeleting automatically..."
        gcloud iam workload-identity-pools undelete github-pool \
          --location=global \
          --project=${var.project_id}
        # Wait for the undelete operation to propagate
        sleep 10
        echo "Pool restored."
      elif [ "$POOL_STATE" = "ACTIVE" ]; then
        echo "Pool is already active — skipping undelete."
      else
        echo "Pool does not exist yet — Terraform will create it."
      fi
    EOT
  }
}

resource "null_resource" "wif_provider_restore" {
  triggers = {
    pool_id     = "github-pool"
    provider_id = "github-provider"
    project_id  = var.project_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      PROVIDER_STATE=$(gcloud iam workload-identity-pools providers describe github-provider \
        --workload-identity-pool=github-pool \
        --location=global \
        --project=${var.project_id} \
        --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

      echo "WIF provider state: $PROVIDER_STATE"

      if [ "$PROVIDER_STATE" = "DELETED" ]; then
        echo "Provider is soft-deleted — undeleting automatically..."
        gcloud iam workload-identity-pools providers undelete github-provider \
          --workload-identity-pool=github-pool \
          --location=global \
          --project=${var.project_id}
        sleep 10
        echo "Provider restored."
      elif [ "$PROVIDER_STATE" = "ACTIVE" ]; then
        echo "Provider is already active — skipping undelete."
      else
        echo "Provider does not exist yet — Terraform will create it."
      fi
    EOT
  }

  depends_on = [null_resource.wif_pool_restore]
}

# ─────────────────────────────────────────────────────────────────────────────
# Workload Identity Pool
# The pool is a container for all external identity providers.
# One pool can have multiple providers (e.g., GitHub, CircleCI, GitLab).
# ─────────────────────────────────────────────────────────────────────────────
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions CI/CD pipelines"
  disabled                  = false

  depends_on = [null_resource.wif_pool_restore]
}

# ─────────────────────────────────────────────────────────────────────────────
# OIDC Provider — GitHub
# Registers GitHub as a trusted OIDC identity provider in the pool.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC Provider"
  description                        = "OIDC provider for GitHub Actions"

  # Attribute mapping: maps JWT claims from GitHub's OIDC token to
  # Google Cloud attributes. These become usable in attribute_condition.
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.workflow"         = "assertion.workflow"
    "attribute.ref"              = "assertion.ref"
  }

  # Security: restrict to ONLY the specified GitHub repository.
  # Without this condition, ANY GitHub user could potentially authenticate.
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  depends_on = [null_resource.wif_provider_restore]
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM Binding — WIF Principal → sa-github-actions
# Allows the GitHub Actions pool to impersonate the sa-github-actions SA.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.github_actions_sa_email}"
  role               = "roles/iam.workloadIdentityUser"

  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

