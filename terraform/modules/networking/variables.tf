# =============================================================================
# modules/networking/variables.tf
# =============================================================================

variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for subnets and Cloud Router."
  type        = string
  default     = "asia-south1"
}

variable "vpc_name" {
  description = "Name of the VPC network."
  type        = string
  default     = "platform-vpc"
}

# ─── Primary subnet CIDRs ────────────────────────────────────────────────────

variable "gke_subnet_cidr" {
  description = "Primary CIDR for the GKE node subnet. Must not overlap with secondary ranges."
  type        = string
  default     = "10.0.0.0/20"
}

variable "management_subnet_cidr" {
  description = "CIDR for the management subnet (bastion, admin VMs)."
  type        = string
  default     = "10.0.16.0/24"
}

variable "proxy_subnet_cidr" {
  description = "CIDR for the proxy subnet (GCP internal load balancers / Gateway API)."
  type        = string
  default     = "10.0.17.0/24"
}

# ─── Secondary IP ranges (GKE alias IPs) ────────────────────────────────────

variable "gke_pods_cidr" {
  description = "Secondary CIDR range for GKE pod IPs. Allocated as alias IPs to node VMs."
  type        = string
  default     = "10.10.0.0/16"
}

variable "gke_services_cidr" {
  description = "Secondary CIDR range for GKE service cluster IPs."
  type        = string
  default     = "10.20.0.0/20"
}
