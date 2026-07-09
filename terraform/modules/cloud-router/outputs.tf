# =============================================================================
# modules/cloud-router/outputs.tf
# =============================================================================

output "router_name" {
  description = "Name of the Cloud Router — consumed by the nat module."
  value       = google_compute_router.router.name
}

output "router_self_link" {
  description = "Self-link URI of the Cloud Router."
  value       = google_compute_router.router.self_link
}

output "router_region" {
  description = "Region of the Cloud Router."
  value       = google_compute_router.router.region
}
