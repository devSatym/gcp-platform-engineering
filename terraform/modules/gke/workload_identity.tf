# =============================================================================
# modules/gke/workload_identity.tf
#
# Workload Identity IAM bindings — Phase 4 implementation.
#
# These bindings link Kubernetes Service Accounts to GCP Service Accounts,
# enabling pods to authenticate to GCP APIs without any JSON key files.
#
# The GKE cluster has Workload Identity ENABLED in cluster.tf
# (workload_pool = "{project}.svc.id.goog").
#
# The GCP Service Accounts were created in Phase 2 (service-accounts module).
# These Terraform resources create the IAM side of the binding.
# The K8s SA annotation side is configured in ArgoCD Helm values (Phase 4).
#
# HOW IT WORKS:
# ─────────────────────────────────────────────────────────────────────────────
#   Pod
#    │  (mounts projected OIDC token for K8s SA)
#    ▼
#   GKE Metadata Server  (intercepts metadata.google.internal)
#    │  (validates token, finds IAM binding below)
#    ▼
#   GCP IAM → issues short-lived access token for the GCP SA
#    ▼
#   GCP SA (sa-argocd / sa-external-secrets) → calls GCP APIs
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD server → sa-argocd
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account_iam_member" "argocd_server_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.argocd_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-server]"
}

resource "google_service_account_iam_member" "argocd_repo_server_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.argocd_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-repo-server]"
}

# ─────────────────────────────────────────────────────────────────────────────
# External Secrets Operator → sa-external-secrets
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.external_secrets_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[platform-system/external-secrets]"
}
