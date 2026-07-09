# =============================================================================
# modules/artifact-registry/outputs.tf
# =============================================================================

output "registry_url" {
  description = "Base URL of the Docker registry. Use as image prefix: {registry_url}/{image}:{tag}"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "repository_id" {
  description = "Repository ID (name) of the Artifact Registry."
  value       = google_artifact_registry_repository.docker.repository_id
}

output "repository_name" {
  description = "Full resource name of the Artifact Registry repository."
  value       = google_artifact_registry_repository.docker.name
}

output "docker_auth_command" {
  description = "Command to configure Docker to push to this registry. Run once before docker push."
  value       = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
}
