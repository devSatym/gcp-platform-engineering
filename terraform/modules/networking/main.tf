# =============================================================================
# modules/networking/main.tf
#
# Creates the platform VPC with a private subnet architecture.
#
# IP Plan:
#   VPC primary:        10.0.0.0/16
#   GKE node subnet:    10.0.0.0/20   (4,094 node IPs)
#   Management subnet:  10.0.16.0/24  (254 IPs — bastion, admin)
#   Proxy subnet:       10.0.17.0/24  (for GCP internal LBs)
#   GKE pods (2nd):     10.10.0.0/16  (65,534 pod IPs)
#   GKE services (2nd): 10.20.0.0/20  (4,094 service IPs)
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# VPC — Custom-mode (no auto-created subnets)
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  project = var.project_id
  name    = var.vpc_name

  # Custom mode: we define every subnet explicitly — no auto-created subnets
  # in regions we don't use, which reduces attack surface.
  auto_create_subnetworks = false

  # REGIONAL routing: routes are only advertised within the region.
  # Change to GLOBAL if you add multi-region clusters later.
  routing_mode = "REGIONAL"

  # MTU 1460 is the default; increase to 1500 if enabling Dataplane V2
  # jumbo frames in Phase 3. Changing MTU requires recreating the VPC.
  mtu = 1460

  description = "Platform Engineering VPC — managed by Terraform"
}

# ─────────────────────────────────────────────────────────────────────────────
# GKE Subnet — Node IPs + secondary ranges for pods and services
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_subnetwork" "gke" {
  project = var.project_id
  name    = "gke-subnet"
  region  = var.region
  network = google_compute_network.vpc.id

  # Primary range — GKE node IP addresses
  ip_cidr_range = var.gke_subnet_cidr

  # Allow nodes to reach Google APIs (Artifact Registry, Secret Manager, etc.)
  # without public IPs — goes via Private Google Access.
  private_ip_google_access = true

  # Secondary ranges — GKE alias IPs for pods and services.
  # These must be declared BEFORE creating the GKE cluster.
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = var.gke_pods_cidr
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = var.gke_services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Management Subnet — Bastion hosts, admin VMs, Cloud Shell connectivity
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_subnetwork" "management" {
  project = var.project_id
  name    = "management-subnet"
  region  = var.region
  network = google_compute_network.vpc.id

  ip_cidr_range            = var.management_subnet_cidr
  private_ip_google_access = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Proxy Subnet — Required for GCP-managed regional internal load balancers
# (used by GKE Gateway API in Phase 9+)
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_subnetwork" "proxy" {
  project = var.project_id
  name    = "proxy-subnet"
  region  = var.region
  network = google_compute_network.vpc.id

  ip_cidr_range = var.proxy_subnet_cidr

  # REGIONAL_MANAGED_PROXY: reserved for Google-managed Envoy proxies
  # used by internal Application Load Balancers and GKE Gateway.
  purpose = "REGIONAL_MANAGED_PROXY"
  role    = "ACTIVE"
}
