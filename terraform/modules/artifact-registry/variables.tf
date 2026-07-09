# =============================================================================
# modules/artifact-registry/variables.tf
# =============================================================================

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the Artifact Registry. Should match the GKE cluster region for fastest pulls."
  type        = string
  default     = "asia-south1"
}

variable "repository_id" {
  description = "Name of the Docker repository. Convention: platform-docker."
  type        = string
  default     = "platform-docker"
}

variable "gke_node_sa_email" {
  description = "GKE node service account email (sa-gke-nodes). Granted artifactregistry.reader to pull images."
  type        = string
}

variable "github_actions_sa_email" {
  description = "GitHub Actions service account email (sa-github-actions). Granted artifactregistry.writer to push images in Phase 6 CI/CD."
  type        = string
}

variable "labels" {
  description = "Labels applied to the Artifact Registry repository."
  type        = map(string)
  default     = {}
}
