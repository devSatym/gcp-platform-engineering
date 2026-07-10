# =============================================================================
# modules/github-wif/outputs.tf
# =============================================================================

output "workload_identity_provider" {
  description = "Full WIF provider resource name for use in google-github-actions/auth. Format: projects/{number}/locations/global/workloadIdentityPools/{pool}/providers/{provider}"
  value       = data.google_iam_workload_identity_pool_provider.github.name
}

output "workload_identity_pool_name" {
  description = "Full WIF pool resource name."
  value       = data.google_iam_workload_identity_pool.github.name
}

output "github_actions_sa_email" {
  description = "GCP SA email that GitHub Actions impersonates via WIF."
  value       = var.github_actions_sa_email
}
