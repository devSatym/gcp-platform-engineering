# =============================================================================
# modules/project/outputs.tf
# =============================================================================

output "project_id" {
  description = "The GCP project ID (pass-through for use in dependent modules)."
  value       = var.project_id
}

output "enabled_apis" {
  description = "Set of GCP APIs that have been enabled."
  value       = [for api in google_project_service.apis : api.service]
}
