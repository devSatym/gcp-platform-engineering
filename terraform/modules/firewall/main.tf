# =============================================================================
# modules/firewall/main.tf
#
# Creates least-privilege firewall rules for the platform VPC.
#
# Rule priority overview (lower number = higher priority):
#   1000  allow-internal        — VPC-internal traffic (node↔node, pod↔pod)
#   1000  allow-iap-ssh         — IAP SSH tunneling (Google's IAP IP range)
#   1000  allow-health-checks   — GCP load balancer health probes
#   65534 deny-all-ingress      — Catch-all deny (GCP's default deny is 65535,
#                                 we set ours at 65534 to make it explicit)
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# ALLOW: Internal VPC traffic
# Permits node-to-node, pod-to-pod, and control-plane-to-node communication.
# Required for GKE to function correctly.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "allow-internal"
  network = var.vpc_name

  description = "Allow all traffic within the VPC internal CIDR range. Required for GKE node-to-node and pod-to-pod communication."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = [var.internal_cidr]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "sctp"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ALLOW: Identity-Aware Proxy (IAP) SSH
# Allows SSH connections tunneled through Google's IAP.
# Never open port 22 to 0.0.0.0/0 — use IAP instead.
# IAP IP range: 35.235.240.0/20 (Google's documented IAP range)
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_firewall" "allow_iap_ssh" {
  project = var.project_id
  name    = "allow-iap-ssh"
  network = var.vpc_name

  description = "Allow SSH via Identity-Aware Proxy. Use IAP tunnel instead of opening port 22 to the internet."
  direction   = "INGRESS"
  priority    = 1000

  # Google's IAP TCP forwarding IP range
  source_ranges = ["35.235.240.0/20"]

  # Only VMs tagged 'allow-iap' receive SSH via IAP.
  # Tag GKE nodes or bastion hosts with this tag as needed.
  target_tags = ["allow-iap"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ALLOW: GCP Health Checks
# Required for Google Load Balancers and GKE internal health probes.
# Source ranges are Google's documented health check IP ranges.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_firewall" "allow_health_checks" {
  project = var.project_id
  name    = "allow-health-checks"
  network = var.vpc_name

  description = "Allow Google Cloud load balancer health check probes. Required for GKE services exposed via LoadBalancer or Ingress."
  direction   = "INGRESS"
  priority    = 1000

  # Google's official health check source ranges
  source_ranges = [
    "35.191.0.0/16",   # Global load balancer health checks
    "130.211.0.0/22",  # Legacy health checks
    "209.85.152.0/22", # Additional health check range
    "209.85.204.0/22", # Additional health check range
  ]

  allow {
    protocol = "tcp"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DENY: All other ingress (explicit default deny)
# GCP has an implicit deny-all at priority 65535.
# We add an explicit one at 65534 to make it visible in the firewall rules list
# and to ensure it appears in firewall logs.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_firewall" "deny_all_ingress" {
  project = var.project_id
  name    = "deny-all-ingress"
  network = var.vpc_name

  description = "Explicit deny-all ingress rule. Makes the default deny visible in firewall rule listings and enables logging of denied traffic."
  direction   = "INGRESS"
  priority    = 65534

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
