# =============================================================================
# modules/networking/outputs.tf
#
# These outputs are consumed by:
#   - cloud-router module (vpc_name)
#   - firewall module (vpc_name, vpc_self_link)
#   - gke module in Phase 3 (gke_subnet_self_link, secondary range names)
# =============================================================================

output "vpc_name" {
  description = "Name of the VPC network."
  value       = google_compute_network.vpc.name
}

output "vpc_id" {
  description = "ID of the VPC network."
  value       = google_compute_network.vpc.id
}

output "vpc_self_link" {
  description = "Self-link URI of the VPC network."
  value       = google_compute_network.vpc.self_link
}

output "gke_subnet_name" {
  description = "Name of the GKE node subnet."
  value       = google_compute_subnetwork.gke.name
}

output "gke_subnet_self_link" {
  description = "Self-link URI of the GKE subnet — used in the GKE cluster resource."
  value       = google_compute_subnetwork.gke.self_link
}

output "gke_subnet_cidr" {
  description = "Primary CIDR of the GKE subnet."
  value       = google_compute_subnetwork.gke.ip_cidr_range
}

output "gke_pods_range_name" {
  description = "Name of the secondary IP range for GKE pods."
  value       = "gke-pods"
}

output "gke_services_range_name" {
  description = "Name of the secondary IP range for GKE services."
  value       = "gke-services"
}

output "management_subnet_name" {
  description = "Name of the management subnet."
  value       = google_compute_subnetwork.management.name
}

output "management_subnet_self_link" {
  description = "Self-link URI of the management subnet."
  value       = google_compute_subnetwork.management.self_link
}

output "proxy_subnet_name" {
  description = "Name of the proxy subnet."
  value       = google_compute_subnetwork.proxy.name
}
