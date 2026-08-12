variable "config" {
  description = "Complete configuration for one independent platform environment. Environment roots provide values; reusable child modules provide implementation."
  type = object({
    project_id   = string
    environment  = string
    region       = string
    cluster_name = string
    labels       = map(string)

    network = object({
      vpc_name               = string
      gke_subnet_cidr        = string
      management_subnet_cidr = string
      proxy_subnet_cidr      = string
      gke_pods_cidr          = string
      gke_services_cidr      = string
    })

    router = object({
      name = string
    })

    nat = object({
      name             = string
      min_ports_per_vm = number
    })

    firewall = object({
      internal_cidr = string
    })

    service_accounts = object({
      secret_ids = set(string)
    })

    gke = object({
      location_type  = optional(string, "regional")
      node_locations = optional(list(string))
      node_pools = map(object({
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
      autoscaling = optional(object({
        enabled = optional(bool, true)
        profile = optional(string, "BALANCED")
      }), {})
      private_cluster = optional(object({
        enabled                 = optional(bool, true)
        enable_private_endpoint = optional(bool, true)
        master_ipv4_cidr_block  = optional(string, "172.16.0.0/28")
        master_authorized_cidrs = optional(list(object({
          cidr_block   = string
          display_name = string
        })), [])
      }), {})
      release_channel                  = optional(string, "REGULAR")
      enable_workload_identity         = optional(bool, true)
      enable_shielded_nodes            = optional(bool, true)
      enable_gateway_api               = optional(bool, true)
      enable_cloud_dns                 = optional(bool, true)
      enable_gcs_fuse_csi              = optional(bool, true)
      enable_vertical_pod_autoscaling  = optional(bool, true)
      enable_managed_prometheus        = optional(bool, true)
      logging_components               = optional(set(string), ["SYSTEM_COMPONENTS", "WORKLOADS"])
      monitoring_components            = optional(set(string), ["SYSTEM_COMPONENTS"])
      binary_authorization_mode        = optional(string, "DISABLED")
      deletion_protection              = optional(bool, true)
      maintenance_start_time           = optional(string)
      maintenance_end_time             = optional(string)
      maintenance_recurrence           = optional(string)
      bootstrap_node_machine_type      = optional(string, "e2-medium")
      bootstrap_node_disk_type         = optional(string, "pd-standard")
      bootstrap_node_disk_size_gb      = optional(number, 30)
      datapath_provider                = optional(string, "ADVANCED_DATAPATH")
      enable_network_policy            = optional(bool, true)
      enable_advanced_datapath_metrics = optional(bool, true)
      enable_datapath_relay            = optional(bool, false)
      enable_http_load_balancing       = optional(bool, true)
      enable_hpa_addon                 = optional(bool, true)
    })

    artifact_registry = object({
      repository_id = string
    })

    github = object({
      repository = string
    })

    argocd = object({
      chart_version = string
      git_repo_url  = string
    })
  })

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.config.environment))
    error_message = "config.environment must be a lowercase DNS-style identifier."
  }

  validation {
    condition     = trimspace(var.config.project_id) != "" && trimspace(var.config.region) != "" && trimspace(var.config.cluster_name) != ""
    error_message = "project_id, region, and cluster_name must not be empty."
  }

  validation {
    condition = alltrue([
      for pool in values(var.config.gke.node_pools) :
      pool.min_count >= 0 && pool.max_count >= pool.min_count
    ])
    error_message = "Every node pool must have non-negative counts and max_count >= min_count."
  }

  validation {
    condition = alltrue([
      for cidr in [
        var.config.network.gke_subnet_cidr,
        var.config.network.management_subnet_cidr,
        var.config.network.proxy_subnet_cidr,
        var.config.network.gke_pods_cidr,
        var.config.network.gke_services_cidr,
        var.config.firewall.internal_cidr,
      ] : can(cidrhost(cidr, 0))
    ])
    error_message = "All network and firewall CIDRs must use valid CIDR notation."
  }

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.config.github.repository))
    error_message = "github.repository must use owner/repository format."
  }
}
