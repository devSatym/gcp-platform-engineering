resource "google_container_node_pool" "pools" {
  for_each = var.node_pools
  provider = google-beta

  project        = var.project_id
  name           = coalesce(each.value.name, each.key)
  location       = var.location_type == "regional" ? var.region : var.node_locations[0]
  node_locations = var.location_type == "regional" ? var.node_locations : null
  cluster        = google_container_cluster.primary.name

  dynamic "autoscaling" {
    for_each = var.autoscaling.enabled ? [1] : []
    content {
      min_node_count = each.value.min_count
      max_node_count = each.value.max_count
    }
  }

  node_count = var.autoscaling.enabled ? null : each.value.min_count

  management {
    auto_repair  = each.value.auto_repair
    auto_upgrade = each.value.auto_upgrade
  }

  node_config {
    machine_type = each.value.machine_type
    disk_type    = each.value.disk_type
    disk_size_gb = each.value.disk_size_gb
    spot         = each.value.spot

    service_account = var.node_service_account
    oauth_scopes    = var.node_oauth_scopes

    workload_metadata_config {
      mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = var.enable_shielded_nodes
      enable_integrity_monitoring = var.enable_shielded_nodes
    }

    labels = merge(var.labels, each.value.labels, {
      pool = each.key
    })

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    tags = each.value.tags
  }

  lifecycle {
    prevent_destroy = false
  }

  # GKE node-pool deletion is asynchronous and can outlast Terraform's
  # default 30-minute wait while the control plane reconciles the cluster.
  timeouts {
    delete = "90m"
  }
}
