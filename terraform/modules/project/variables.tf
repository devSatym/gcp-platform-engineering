# =============================================================================
# modules/project/variables.tf
# =============================================================================

variable "project_id" {
  description = "The GCP project ID in which to enable APIs."
  type        = string
}

variable "labels" {
  description = "Labels to apply to project-level resources (not all resources support project-level labels directly)."
  type        = map(string)
  default     = {}
}
