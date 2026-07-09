# =============================================================================
# modules/cloud-router/variables.tf
# =============================================================================

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "asia-south1"
}

variable "router_name" {
  description = "Name of the Cloud Router."
  type        = string
  default     = "platform-router"
}

variable "vpc_name" {
  description = "Name of the VPC network to associate the router with."
  type        = string
}
