# =============================================================================
# modules/github-wif/outputs.tf
# =============================================================================

output "workload_identity_provider" {
  description = "Full WIF provider resource name for use in google-github-actions/auth. Format: projects/{number}/locations/global/workloadIdentityPools/{pool}/providers/{provider}"
  value       = local.wif_provider_name
}

output "workload_identity_pool_name" {
  description = "Full WIF pool resource name."
  value       = local.wif_pool_name
}

output "github_actions_sa_email" {
  description = "GCP SA email that GitHub Actions impersonates via WIF."
  value       = var.github_actions_sa_email
}
