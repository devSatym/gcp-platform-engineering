# =============================================================================
# modules/firewall/variables.tf
# =============================================================================

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "vpc_name" {
  description = "Name of the VPC network to apply firewall rules to."
  type        = string
}

variable "internal_cidr" {
  description = "CIDR range considered internal (VPC primary range). All traffic within this range is allowed."
  type        = string
  default     = "10.0.0.0/16"
}
