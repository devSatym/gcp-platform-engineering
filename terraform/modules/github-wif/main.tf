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
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions CI/CD pipelines"
  disabled                  = false
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
    "google.subject"             = "assertion.sub"                    # e.g. repo:owner/repo:ref:refs/heads/main
    "attribute.actor"            = "assertion.actor"                  # GitHub username who triggered the workflow
    "attribute.repository"       = "assertion.repository"             # e.g. "owner/repo"
    "attribute.repository_owner" = "assertion.repository_owner"       # e.g. "owner"
    "attribute.workflow"         = "assertion.workflow"                # Workflow name
    "attribute.ref"              = "assertion.ref"                     # Branch/tag ref
  }

  # Security: restrict to ONLY the specified GitHub repository.
  # Without this condition, ANY GitHub user could potentially authenticate.
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM Binding — WIF Principal → sa-github-actions
# Allows the GitHub Actions pool to impersonate the sa-github-actions SA.
# The principal is all identities from our GitHub repo in the WIF pool.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.github_actions_sa_email}"
  role               = "roles/iam.workloadIdentityUser"

  # principalSet: grants access to ALL identities from the specified repo
  # in our WIF pool. This covers all branches, tags, and workflow triggers.
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
