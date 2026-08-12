variable "project_id" {
  description = "GCP project ID that owns the cluster."
  type        = string
  validation {
    condition     = trimspace(var.project_id) != ""
    error_message = "project_id must not be empty."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.cluster_name)) && length(var.cluster_name) <= 40
    error_message = "cluster_name must be lowercase, use only letters, numbers, and hyphens, and be at most 40 characters."
  }
}

variable "region" {
  description = "GCP region in which to create the regional cluster."
  type        = string
  validation {
    condition     = trimspace(var.region) != ""
    error_message = "region must not be empty."
  }
}

variable "location_type" {
  description = "Whether the cluster control plane is regional or zonal. Zonal clusters are suitable for low-cost development; regional clusters provide higher availability."
  type        = string
  default     = "regional"

  validation {
    condition     = contains(["regional", "zonal"], var.location_type)
    error_message = "location_type must be regional or zonal."
  }
}

variable "node_locations" {
  description = "Optional list of zones in the region where nodes may run."
  type        = list(string)
  default     = null
}

variable "network_name" {
  description = "Name or self-link of the VPC network."
  type        = string
}

variable "subnetwork_name" {
  description = "Name or self-link of the subnet used by GKE nodes."
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Name of the subnet secondary range used for pod IPs."
  type        = string
}

variable "services_secondary_range_name" {
  description = "Name of the subnet secondary range used for service IPs."
  type        = string
}

variable "node_service_account" {
  description = "Email address of the dedicated service account used by GKE nodes."
  type        = string
}

variable "node_oauth_scopes" {
  description = "OAuth scopes attached to GKE node VMs. IAM roles remain the primary authorization control."
  type        = set(string)
  default = [
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/servicecontrol",
    "https://www.googleapis.com/auth/service.management.readonly",
    "https://www.googleapis.com/auth/trace.append",
  ]
  validation {
    condition     = length(var.node_oauth_scopes) > 0
    error_message = "node_oauth_scopes must contain at least one scope."
  }
}

variable "node_pools" {
  description = "Node pools to create, keyed by caller-defined logical name."
  type = map(object({
    machine_type = string
    name         = optional(string)
    min_count    = number
    max_count    = number
    disk_type    = optional(string, "pd-standard")
    disk_size_gb = optional(number, 50)
    spot         = optional(bool, false)
    labels       = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    tags         = optional(list(string), [])
    auto_repair  = optional(bool, true)
    auto_upgrade = optional(bool, true)
  }))

  validation {
    condition = alltrue([
      for key, pool in var.node_pools :
      can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", coalesce(pool.name, key))) &&
      length(coalesce(pool.name, key)) <= 40 &&
      pool.min_count >= 0 &&
      pool.max_count >= pool.min_count &&
      pool.disk_size_gb > 0 &&
      alltrue([for taint in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)])
    ])
    error_message = "Node pools must have valid names, non-negative counts, positive disks, and valid taint effects."
  }
}

variable "autoscaling" {
  description = "Cluster autoscaling settings. Node-pool min/max limits remain in node_pools."
  type = object({
    enabled = optional(bool, true)
    profile = optional(string, "BALANCED")
  })
  default = {}

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling.profile)
    error_message = "autoscaling.profile must be BALANCED or OPTIMIZE_UTILIZATION."
  }
}

variable "private_cluster" {
  description = "Private-cluster and control-plane access settings."
  type = object({
    enabled                 = optional(bool, true)
    enable_private_endpoint = optional(bool, true)
    master_ipv4_cidr_block  = optional(string, "172.16.0.0/28")
    master_authorized_cidrs = optional(list(object({
      cidr_block   = string
      display_name = string
    })), [])
  })
  default = {}

  validation {
    condition = alltrue([
      for block in var.private_cluster.master_authorized_cidrs :
      can(cidrhost(block.cidr_block, 0))
    ])
    error_message = "Every authorized control-plane network must use valid CIDR notation."
  }

  validation {
    condition = (
      !var.private_cluster.enabled ||
      can(cidrhost(var.private_cluster.master_ipv4_cidr_block, 0))
    )
    error_message = "master_ipv4_cidr_block must be valid CIDR notation."
  }

  validation {
    condition = (
      !var.private_cluster.enabled ||
      can(cidrhost(var.private_cluster.master_ipv4_cidr_block, 0))
    )
    error_message = "master_ipv4_cidr_block must be valid CIDR notation."
  }
}

variable "labels" {
  description = "Common labels applied to the cluster and merged into every node pool."
  type        = map(string)
  default     = {}
}

variable "release_channel" {
  description = "GKE release channel."
  type        = string
  default     = "REGULAR"
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "enable_workload_identity" {
  description = "Whether to enable the GKE Workload Identity pool."
  type        = bool
  default     = true
}

variable "enable_shielded_nodes" {
  description = "Whether to enable Shielded GKE nodes."
  type        = bool
  default     = true
}

variable "enable_gateway_api" {
  description = "Whether to enable the GKE Gateway API integration."
  type        = bool
  default     = true
}

variable "enable_cloud_dns" {
  description = "Whether to use Cloud DNS for cluster-scoped DNS."
  type        = bool
  default     = true
}

variable "enable_gcs_fuse_csi" {
  description = "Whether to enable the GCS Fuse CSI driver addon."
  type        = bool
  default     = true
}

variable "enable_vertical_pod_autoscaling" {
  description = "Whether to enable the GKE VPA addon."
  type        = bool
  default     = true
}

variable "enable_managed_prometheus" {
  description = "Whether to enable GKE Managed Service for Prometheus."
  type        = bool
  default     = true
}

variable "logging_components" {
  description = "GKE logging components to export."
  type        = set(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "monitoring_components" {
  description = "GKE monitoring components to export."
  type        = set(string)
  default     = ["SYSTEM_COMPONENTS"]
}

variable "binary_authorization_mode" {
  description = "Binary Authorization evaluation mode."
  type        = string
  default     = "DISABLED"
  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_mode)
    error_message = "binary_authorization_mode must be DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE."
  }
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental deletion."
  type        = bool
  default     = true
}

variable "maintenance_start_time" {
  description = "RFC3339 start time for the recurring maintenance window."
  type        = string
  default     = null
}

variable "maintenance_end_time" {
  description = "RFC3339 end time for the recurring maintenance window."
  type        = string
  default     = null
}

variable "maintenance_recurrence" {
  description = "RFC5545 recurrence rule for the maintenance window."
  type        = string
  default     = null
}

variable "bootstrap_node_machine_type" {
  description = "Machine type used only while GKE creates the temporary default node pool."
  type        = string
  default     = "e2-medium"
}

variable "bootstrap_node_disk_type" {
  description = "Disk type used only by the temporary default node pool."
  type        = string
  default     = "pd-standard"
}

variable "bootstrap_node_disk_size_gb" {
  description = "Disk size used only by the temporary default node pool."
  type        = number
  default     = 30
  validation {
    condition     = var.bootstrap_node_disk_size_gb > 0
    error_message = "bootstrap_node_disk_size_gb must be greater than zero."
  }
}

variable "datapath_provider" {
  description = "GKE datapath provider."
  type        = string
  default     = "ADVANCED_DATAPATH"
  validation {
    condition     = contains(["ADVANCED_DATAPATH", "LEGACY_DATAPATH"], var.datapath_provider)
    error_message = "datapath_provider must be ADVANCED_DATAPATH or LEGACY_DATAPATH."
  }
}

variable "enable_network_policy" {
  description = "Whether to enable the standard network-policy addon when using the legacy datapath."
  type        = bool
  default     = true
}

variable "enable_advanced_datapath_metrics" {
  description = "Whether to enable Dataplane V2 observability metrics."
  type        = bool
  default     = true
}

variable "enable_datapath_relay" {
  description = "Whether to enable Dataplane V2 observability relay."
  type        = bool
  default     = false
}

variable "enable_http_load_balancing" {
  description = "Whether to enable the GKE HTTP load-balancing addon."
  type        = bool
  default     = true
}

variable "enable_hpa_addon" {
  description = "Whether to enable the GKE HPA addon."
  type        = bool
  default     = true
}
