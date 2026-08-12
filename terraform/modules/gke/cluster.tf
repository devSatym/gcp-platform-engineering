resource "google_container_cluster" "primary" {
  provider = google-beta

  project  = var.project_id
  name     = var.cluster_name
  location = var.location_type == "regional" ? var.region : var.node_locations[0]

  node_locations = var.location_type == "regional" ? var.node_locations : null
  network        = var.network_name
  subnetwork     = var.subnetwork_name

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  dynamic "private_cluster_config" {
    for_each = var.private_cluster.enabled ? [var.private_cluster] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = private_cluster_config.value.enable_private_endpoint
      master_ipv4_cidr_block  = private_cluster_config.value.master_ipv4_cidr_block
    }
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.private_cluster.master_authorized_cidrs) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.private_cluster.master_authorized_cidrs
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  datapath_provider = var.datapath_provider

  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }

  enable_shielded_nodes = var.enable_shielded_nodes

  binary_authorization {
    evaluation_mode = var.binary_authorization_mode
  }

  dynamic "gateway_api_config" {
    for_each = var.enable_gateway_api ? [1] : []
    content {
      channel = "CHANNEL_STANDARD"
    }
  }

  dynamic "vertical_pod_autoscaling" {
    for_each = var.enable_vertical_pod_autoscaling ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "dns_config" {
    for_each = var.enable_cloud_dns ? [1] : []
    content {
      cluster_dns       = "CLOUD_DNS"
      cluster_dns_scope = "CLUSTER_SCOPE"
    }
  }

  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = var.monitoring_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }

    advanced_datapath_observability_config {
      enable_metrics = var.enable_advanced_datapath_metrics
      enable_relay   = var.enable_datapath_relay
    }
  }

  dynamic "cluster_autoscaling" {
    for_each = var.autoscaling.enabled ? [1] : []
    content {
      autoscaling_profile = var.autoscaling.profile
    }
  }

  dynamic "maintenance_policy" {
    for_each = var.maintenance_start_time != null && var.maintenance_end_time != null && var.maintenance_recurrence != null ? [1] : []
    content {
      recurring_window {
        start_time = var.maintenance_start_time
        end_time   = var.maintenance_end_time
        recurrence = var.maintenance_recurrence
      }
    }
  }

  addons_config {
    http_load_balancing {
      disabled = !var.enable_http_load_balancing
    }

    horizontal_pod_autoscaling {
      disabled = !var.enable_hpa_addon
    }

    dynamic "network_policy_config" {
      for_each = var.datapath_provider == "ADVANCED_DATAPATH" ? [] : [1]
      content {
        disabled = !var.enable_network_policy
      }
    }

    gcs_fuse_csi_driver_config {
      enabled = var.enable_gcs_fuse_csi
    }
  }

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  resource_labels          = var.labels

  lifecycle {
    precondition {
      condition = (
        (var.maintenance_start_time == null && var.maintenance_end_time == null && var.maintenance_recurrence == null) ||
        (var.maintenance_start_time != null && var.maintenance_end_time != null && var.maintenance_recurrence != null)
      )
      error_message = "Maintenance window settings must be provided all together or all omitted."
    }

    precondition {
      condition     = var.autoscaling.enabled || alltrue([for pool in values(var.node_pools) : pool.min_count == pool.max_count])
      error_message = "When autoscaling is disabled, every node pool must have min_count equal to max_count."
    }
  }
}
