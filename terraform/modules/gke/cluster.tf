# =============================================================================
# modules/gke/cluster.tf
#
# Defines the google_container_cluster resource — the private, regional, hardened
# GKE cluster that is the Kubernetes platform for this project.
#
# Design decisions documented in: docs/adr/001-why-gke.md
#                                  docs/adr/004-why-private-cluster.md
# =============================================================================

resource "google_container_cluster" "primary" {
  provider = google-beta # Required for some beta features (gateway_api_config, etc.)

  project  = var.project_id
  name     = var.cluster_name
  location = var.region # Regional cluster — HA across all 3 zones in asia-south1

  # ─── Network ──────────────────────────────────────────────────────────────
  # Attach to the VPC and GKE subnet provisioned in Phase 2.
  network    = var.vpc_name
  subnetwork = var.gke_subnet_name

  # VPC-native (alias IP) cluster — required for Dataplane V2 and private GKE.
  # Secondary IP ranges declared in Phase 2 networking module are referenced here.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.gke_pods_range_name    # "gke-pods" → 10.10.0.0/16
    services_secondary_range_name = var.gke_services_range_name # "gke-services" → 10.20.0.0/20
  }

  # ─── Private Cluster ──────────────────────────────────────────────────────
  # Nodes have no public IPs. Outbound internet goes via Cloud NAT (Phase 2).
  private_cluster_config {
    enable_private_nodes = true

    # enable_private_endpoint = false: API server has a public endpoint.
    # This is intentional for dev — allows kubectl from local machine + Cloud Shell.
    # For prod: set to true and use an IAP tunnel or bastion.
    enable_private_endpoint = var.enable_private_endpoint

    # Control plane CIDR — must not overlap with VPC, pods, or services ranges.
    # /28 is the minimum block required by GKE.
    master_ipv4_cidr_block = var.master_ipv4_cidr_block
  }

  # Restrict API server access to specific CIDRs.
  # Dev: 0.0.0.0/0 (open, protected by GKE auth).
  # Stage/prod: restrict to your VPN/bastion CIDR.
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.master_authorized_cidr
      display_name = "Authorized access (${var.cluster_name})"
    }
  }

  # ─── Kubernetes Version ───────────────────────────────────────────────────
  # REGULAR channel: predictable managed patch + minor upgrades.
  # GKE handles patch upgrades automatically; minor upgrades are controlled.
  release_channel {
    channel = "REGULAR"
  }

  # ─── Dataplane V2 — eBPF Networking ───────────────────────────────────────
  # Replaces kube-proxy and iptables with eBPF (Cilium-based).
  # Benefits: better network policy performance, lower latency, richer observability.
  # ADVANCED_DATAPATH_V2 enables Network Policies automatically.
  datapath_provider = "ADVANCED_DATAPATH"

  # Network policy is implicitly enabled by Dataplane V2.
  # Explicit declaration for documentation clarity.
  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED" # Dataplane V2 is the provider
  }

  # ─── Workload Identity ────────────────────────────────────────────────────
  # Enables keyless pod-to-GCP-SA authentication.
  # Pods use their Kubernetes SA to assume a GCP SA — no JSON key files.
  # Phase 4 configures the actual K8s SA → GCP SA bindings.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Metadata server is required for Workload Identity to function.
  # Blocks legacy metadata APIs that could leak SA tokens.
  node_config {
    # This default node pool is removed immediately after cluster creation.
    # Its config is irrelevant but must be specified.
    machine_type = "e2-medium"
    service_account = var.gke_node_sa_email
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA" # Enables Workload Identity on nodes
    }
  }

  # ─── Shielded Nodes ───────────────────────────────────────────────────────
  # Secure Boot + vTPM + Integrity Monitoring at the node VM level.
  # Protects against boot-level rootkits and unauthorized modifications.
  enable_shielded_nodes = true

  # ─── Binary Authorization ─────────────────────────────────────────────────
  # Phase 7 will configure actual policies (image signing via Cosign).
  # DISABLED here — switching to ENFORCE in Phase 7 after pipeline is ready.
  binary_authorization {
    evaluation_mode = "DISABLED"
  }

  # ─── Gateway API ──────────────────────────────────────────────────────────
  # Enables the GKE Gateway API controller — prerequisite for Istio Gateway (Phase 9)
  # and the proxy-subnet we created in Phase 2.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # ─── Vertical Pod Autoscaler ──────────────────────────────────────────────
  # VPA recommends optimal CPU/memory requests per container.
  # Actual HPA/VPA policies are configured in Phase 11.
  vertical_pod_autoscaling {
    enabled = local.enable_vpa
  }

  # ─── Cloud DNS ────────────────────────────────────────────────────────────
  # Use Cloud DNS instead of kube-dns for in-cluster DNS resolution.
  # Lower latency, better scalability, integrates with Cloud DNS zones.
  dns_config {
    cluster_dns        = "CLOUD_DNS"
    cluster_dns_scope  = "CLUSTER_SCOPE"
  }

  # ─── Logging ──────────────────────────────────────────────────────────────
  # Exports to Cloud Logging. Components defined in logging.tf locals.
  logging_config {
    enable_components = local.logging_components
  }

  # ─── Monitoring ───────────────────────────────────────────────────────────
  # Exports to Cloud Monitoring. Config defined in monitoring.tf locals.
  monitoring_config {
    enable_components = local.monitoring_components

    # GCP-managed Prometheus scraping — complements in-cluster Prometheus (Phase 8).
    managed_prometheus {
      enabled = local.enable_managed_prometheus
    }

    # eBPF-level network flow metrics from Dataplane V2.
    advanced_datapath_observability_config {
      enable_metrics = true
    }
  }

  # ─── Maintenance Window ───────────────────────────────────────────────────
  # Weekday maintenance: Mon–Fri 02:00–06:00 IST (UTC 20:30–00:30 previous day).
  # Avoids peak business hours for patch upgrades.
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-01T20:30:00Z"
      end_time   = "2026-01-02T00:30:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    }
  }

  # ─── Cluster Addons ───────────────────────────────────────────────────────
  addons_config {
    # HTTP Load Balancing — required for GKE Ingress and Gateway API.
    http_load_balancing {
      disabled = false
    }

    # Horizontal Pod Autoscaler — enabled, configured in Phase 11.
    horizontal_pod_autoscaling {
      disabled = false
    }

    # GKE Dashboard — kubernetes_dashboard addon was removed in provider v5+.
    # Use Cloud Console for cluster monitoring instead.

    # Network Policy — handled by Dataplane V2, not this addon.
    network_policy_config {
      disabled = true
    }

    # GCS Fuse CSI driver — for mounting Cloud Storage as a volume (future phases).
    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }

  # ─── Default Node Pool Removal ────────────────────────────────────────────
  # GKE requires at least one node to create the cluster.
  # We immediately remove the default pool and manage our own in nodepools.tf.
  remove_default_node_pool = true
  initial_node_count       = 1

  # ─── Deletion Protection ──────────────────────────────────────────────────
  # Set to false for portfolio — allows terraform destroy.
  # Production: set to true to prevent accidental deletion.
  deletion_protection = false

  # ─── Resource Labels ──────────────────────────────────────────────────────
  resource_labels = var.labels

  # ─── Lifecycle ────────────────────────────────────────────────────────────
  lifecycle {
    # Prevent Terraform from destroying and recreating the cluster
    # if the min_master_version changes due to GKE auto-upgrades.
    ignore_changes = [
      node_config,
      min_master_version,
    ]
  }

  # GKE depends on networking and NAT being ready first.
  depends_on = [var.depends_on_nat]
}
