# =============================================================================
# modules/gke/variables.tf
# =============================================================================

# ─── Core ─────────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the regional cluster (e.g. asia-south1). Cluster spans all 3 zones."
  type        = string
  default     = "asia-south1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Convention: otel-{env}-gke."
  type        = string
}

# ─── Networking (from Phase 2 outputs) ────────────────────────────────────────

variable "vpc_name" {
  description = "Name of the VPC network. From networking module output."
  type        = string
}

variable "gke_subnet_name" {
  description = "Name of the GKE node subnet. From networking module output."
  type        = string
}

variable "gke_pods_range_name" {
  description = "Secondary IP range name for GKE pods (alias IPs). From networking module output."
  type        = string
  default     = "gke-pods"
}

variable "gke_services_range_name" {
  description = "Secondary IP range name for GKE services. From networking module output."
  type        = string
  default     = "gke-services"
}

# ─── IAM (from Phase 2 service-accounts module) ───────────────────────────────

variable "gke_node_sa_email" {
  description = "Email of the GKE node service account (sa-gke-nodes). From service-accounts module output."
  type        = string
}

variable "argocd_sa_email" {
  description = "GCP SA email for ArgoCD Workload Identity binding. From service-accounts module output."
  type        = string
  default     = ""
}

variable "external_secrets_sa_email" {
  description = "GCP SA email for External Secrets Operator Workload Identity binding. From service-accounts module output."
  type        = string
  default     = ""
}

# ─── Private Cluster ──────────────────────────────────────────────────────────

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the GKE control plane. Must be /28 and not overlap with VPC, pods, or services ranges."
  type        = string
  default     = "172.16.0.0/28"
}

variable "enable_private_endpoint" {
  description = "If true, the API server is only accessible from within the VPC (requires bastion or IAP). Set false for dev, true for prod."
  type        = bool
  default     = false
}

variable "master_authorized_cidr" {
  description = "CIDR allowed to reach the GKE API server. Use 0.0.0.0/0 for dev, restrict to VPN/bastion CIDR for prod."
  type        = string
  default     = "0.0.0.0/0"
}

# ─── System Node Pool ─────────────────────────────────────────────────────────

variable "system_pool_machine_type" {
  description = "Machine type for system node pool. e2-medium is sufficient for platform components."
  type        = string
  default     = "e2-medium"
}

variable "system_pool_min_count" {
  description = "Min nodes per zone in system pool. Should always be at least 1 for platform availability."
  type        = number
  default     = 1
}

variable "system_pool_max_count" {
  description = "Max nodes per zone in system pool."
  type        = number
  default     = 2
}

# ─── General Node Pool ────────────────────────────────────────────────────────

variable "general_pool_machine_type" {
  description = "Machine type for general node pool. e2-standard-4 (4 vCPU, 16 GB) suits OTel Demo services."
  type        = string
  default     = "e2-standard-4"
}

variable "general_pool_min_count" {
  description = "Min nodes per zone in general pool."
  type        = number
  default     = 1
}

variable "general_pool_max_count" {
  description = "Max nodes per zone in general pool. Keep lower in dev to control costs."
  type        = number
  default     = 5
}

# ─── Spot Node Pool ───────────────────────────────────────────────────────────

variable "spot_pool_machine_type" {
  description = "Machine type for spot node pool. e2-standard-2 balances cost and capacity for non-critical workloads."
  type        = string
  default     = "e2-standard-2"
}

variable "spot_pool_min_count" {
  description = "Min nodes per zone in spot pool. 0 allows scaling to zero when unused."
  type        = number
  default     = 0
}

variable "spot_pool_max_count" {
  description = "Max nodes per zone in spot pool. Acts as a cost guard."
  type        = number
  default     = 3
}

# ─── Labels ───────────────────────────────────────────────────────────────────

variable "labels" {
  description = "Labels applied to the cluster and node pools."
  type        = map(string)
  default     = {}
}

# ─── Dependency passthrough ───────────────────────────────────────────────────
# Terraform doesn't support cross-module depends_on for non-resource values.
# This variable allows the environment to pass a dependency signal.

variable "depends_on_nat" {
  description = "Pass the NAT module output here to ensure NAT is ready before GKE. Set to module.nat.nat_name."
  type        = any
  default     = null
}
