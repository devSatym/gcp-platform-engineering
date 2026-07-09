# =============================================================================
# modules/service-accounts/outputs.tf
#
# These email outputs are consumed by:
#   - gke module (Phase 3): gke_node_sa_email → cluster node_config.service_account
#   - argocd helm values (Phase 4): argocd_sa_email → Workload Identity annotation
#   - external-secrets helm values (Phase 4): external_secrets_sa_email
#   - github WIF config (Phase 6): github_actions_sa_email
# =============================================================================

output "gke_node_sa_email" {
  description = "Email of the GKE node service account. Used in node pool configuration."
  value       = google_service_account.gke_nodes.email
}

output "gke_node_sa_name" {
  description = "Fully-qualified name of the GKE node SA."
  value       = google_service_account.gke_nodes.name
}

output "argocd_sa_email" {
  description = "Email of the ArgoCD service account for Workload Identity binding."
  value       = google_service_account.argocd.email
}

output "external_secrets_sa_email" {
  description = "Email of the External Secrets Operator SA for Workload Identity binding."
  value       = google_service_account.external_secrets.email
}

output "github_actions_sa_email" {
  description = "Email of the GitHub Actions SA for Workload Identity Federation."
  value       = google_service_account.github_actions.email
}
