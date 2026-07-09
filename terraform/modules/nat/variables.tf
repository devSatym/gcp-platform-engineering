# =============================================================================
# modules/nat/variables.tf
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

variable "nat_name" {
  description = "Name of the Cloud NAT gateway."
  type        = string
  default     = "platform-nat"
}

variable "router_name" {
  description = "Name of the Cloud Router to attach NAT to."
  type        = string
}

variable "min_ports_per_vm" {
  description = "Minimum number of NAT ports allocated per VM. Increase if pod port exhaustion occurs."
  type        = number
  default     = 64
}
