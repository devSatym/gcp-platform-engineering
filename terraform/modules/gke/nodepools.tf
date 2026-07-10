# =============================================================================
# modules/gke/nodepools.tf
#
# Defines three node pools with distinct purposes, sizing, and scheduling.
#
# Pool philosophy (from docs/architecture/kubernetes-architecture.md):
#
#   system-pool  → Platform-critical components (ArgoCD, Prometheus, Istio)
#                  Always on. Small. Tainted so only system workloads schedule here.
#
#   general-pool → Business microservices (OTel Demo services)
#                  Elastic. Autoscaling. The workhorse pool.
#
#   spot-pool    → Non-critical, interruptible workloads (Load Generator, Chaos)
#                  Cheap. Can scale to zero. Pods must tolerate interruption.
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM POOL — Platform-critical workloads only
# ─────────────────────────────────────────────────────────────────────────────
resource "google_container_node_pool" "system" {
  provider = google-beta

  project  = var.project_id
  name     = "system-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  # Node count per zone — with 3 zones in asia-south1, min=1 means 3 total nodes.
  autoscaling {
    min_node_count = var.system_pool_min_count # 1
    max_node_count = var.system_pool_max_count # 2
  }

  management {
    auto_repair  = true # Automatically repair unhealthy nodes
    auto_upgrade = true # Upgrade nodes with cluster release channel
  }

  node_config {
    machine_type = var.system_pool_machine_type # e2-medium (2 vCPU, 4 GB)
    disk_type    = "pd-standard"
    disk_size_gb = 50  # OS + ArgoCD/ESO/Prometheus/Falco images

    # Use the dedicated GKE node SA — never the default Compute SA.
    service_account = var.gke_node_sa_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Workload Identity — GKE_METADATA mode enables the metadata server
    # that allows pods to obtain GCP credentials via their K8s service account.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Shielded instance config — Secure Boot prevents unsigned kernel/bootloader loading.
    # Integrity Monitoring detects runtime modifications to the boot chain.
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Node labels — used by nodeSelector and affinity rules in pod specs.
    labels = merge(var.labels, {
      workload    = "system"
      pool        = "system-pool"
      environment = lookup(var.labels, "environment", "dev")
    })

    # Taint: CriticalAddonsOnly — prevents non-system pods from scheduling here.
    # Pods that should run on system nodes must tolerate this taint:
    #   tolerations:
    #   - key: "workload"
    #     operator: "Equal"
    #     value: "system"
    #     effect: "NoSchedule"
    taint {
      key    = "workload"
      value  = "system"
      effect = "NO_SCHEDULE"
    }

    # Node-level metadata — disables legacy metadata endpoint.
    metadata = {
      disable-legacy-endpoints = "true"
    }

    tags = ["gke-node", "system-pool"]
  }

  lifecycle {
    ignore_changes = [node_config[0].resource_labels]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# GENERAL POOL — Business microservices (OTel Demo)
# ─────────────────────────────────────────────────────────────────────────────
resource "google_container_node_pool" "general" {
  provider = google-beta

  project  = var.project_id
  name     = "general-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.general_pool_min_count # 1 (at least 1 node per zone always)
    max_node_count = var.general_pool_max_count # 5 (elastic scaling for load spikes)
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.general_pool_machine_type # e2-standard-4 (4 vCPU, 16 GB)
    disk_type    = "pd-standard"
    disk_size_gb = 80  # OTel demo images (~2-3GB each) + observability stack

    service_account = var.gke_node_sa_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # No taint — general pool accepts all pods that don't have specific constraints.
    # This is the "default" landing zone for OTel Demo microservices.
    labels = merge(var.labels, {
      workload    = "general"
      pool        = "general-pool"
      environment = lookup(var.labels, "environment", "dev")
    })

    metadata = {
      disable-legacy-endpoints = "true"
    }

    tags = ["gke-node", "general-pool"]
  }

  lifecycle {
    ignore_changes = [node_config[0].resource_labels]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# SPOT POOL — Non-critical, interruptible workloads
# ─────────────────────────────────────────────────────────────────────────────
resource "google_container_node_pool" "spot" {
  provider = google-beta

  project  = var.project_id
  name     = "spot-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.spot_pool_min_count # 0 — can scale to zero when unused
    max_node_count = var.spot_pool_max_count # 3 — cost guard
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.spot_pool_machine_type # e2-standard-2 (2 vCPU, 8 GB)
    disk_type    = "pd-standard"
    disk_size_gb = 50  # Standard — spot nodes pull images on demand

    # Spot VMs — up to 91% cheaper than on-demand, but can be preempted with 30s notice.
    # Only schedule workloads here that can handle sudden termination gracefully.
    spot = true

    service_account = var.gke_node_sa_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(var.labels, {
      workload    = "spot"
      pool        = "spot-pool"
      environment = lookup(var.labels, "environment", "dev")
    })

    # Taint: workload=spot:NoSchedule — only pods that explicitly tolerate spot preemption
    # should land here. Prevents production services from accidentally scheduling on spot.
    # Pods must include:
    #   tolerations:
    #   - key: "workload"
    #     operator: "Equal"
    #     value: "spot"
    #     effect: "NoSchedule"
    taint {
      key    = "workload"
      value  = "spot"
      effect = "NO_SCHEDULE"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    tags = ["gke-node", "spot-pool"]
  }

  lifecycle {
    ignore_changes = [node_config[0].resource_labels]
  }
}
