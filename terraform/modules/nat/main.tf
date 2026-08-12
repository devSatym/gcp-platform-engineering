# =============================================================================
# modules/nat/main.tf
#
# Creates Cloud NAT to provide outbound internet access for private GKE nodes.
#
# Private GKE nodes have no public IPs. They need outbound access for:
#   - Pulling container images from public registries (bootstrap only)
#   - Pulling images from Artifact Registry via Private Google Access
#   - Package managers during node startup scripts
#   - External API calls from cluster components and workloads
# =============================================================================

resource "google_compute_router_nat" "nat" {
  project = var.project_id
  name    = var.nat_name
  router  = var.router_name
  region  = var.region

  # AUTO_ONLY: GCP allocates and manages external IPs automatically.
  # Use MANUAL_ONLY if you need deterministic egress IPs for allowlisting.
  nat_ip_allocate_option = "AUTO_ONLY"

  # Nat all subnets in the region. More targeted configuration can be
  # applied later to restrict which subnets use NAT.
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Minimum ports per VM instance.
  # Default 64. Increase if you see port exhaustion errors.
  # 64 supports ~64 concurrent connections per pod per destination.
  min_ports_per_vm = 64

  # Enable NAT logging for errors — useful for debugging connection failures.
  # Use "ALL" for full visibility but higher Cloud Logging cost.
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  # TCP session timeouts (seconds)
  tcp_established_idle_timeout_sec = 1200 # 20 min (GCP default)
  tcp_transitory_idle_timeout_sec  = 30
  tcp_time_wait_timeout_sec        = 120

  # UDP session timeout
  udp_idle_timeout_sec = 30

  # ICMP timeout
  icmp_idle_timeout_sec = 30
}
