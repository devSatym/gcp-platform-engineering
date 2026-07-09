# =============================================================================
# environments/dev/variables.tf
# =============================================================================

variable "project_id" {
  description = "GCP project ID. Set in terraform.tfvars."
  type        = string
}

variable "region" {
  description = "Primary GCP region."
  type        = string
  default     = "asia-south1"
}

variable "environment" {
  description = "Environment name — used in labels and resource naming."
  type        = string
  default     = "dev"
}
