# =============================================================================
# modules/cloud-router/main.tf
#
# Creates a Cloud Router to support Cloud NAT.
# Cloud Router manages BGP sessions and advertises routes for NAT.
# =============================================================================

resource "google_compute_router" "router" {
  project = var.project_id
  name    = var.router_name
  region  = var.region
  network = var.vpc_name

  # BGP settings — used for dynamic routing. Even though we're not doing
  # Interconnect or VPN here, the ASN must be set.
  bgp {
    asn = 64514 # Private ASN range: 64512–65534
  }

  description = "Platform Cloud Router for NAT — managed by Terraform"
}
