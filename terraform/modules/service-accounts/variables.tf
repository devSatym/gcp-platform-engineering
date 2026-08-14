# =============================================================================
# modules/service-accounts/variables.tf
# =============================================================================

variable "project_id" {
  description = "GCP project ID in which to create service accounts."
  type        = string
}

variable "secret_ids" {
  description = "Secret Manager secret resource IDs that ESO may read."
  type        = set(string)
  default     = []
}
