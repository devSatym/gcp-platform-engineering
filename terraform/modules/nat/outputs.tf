# =============================================================================
# modules/nat/outputs.tf
# =============================================================================

output "nat_name" {
  description = "Name of the Cloud NAT gateway."
  value       = google_compute_router_nat.nat.name
}
