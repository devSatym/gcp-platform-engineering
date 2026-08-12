output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_id" {
  description = "Unique identifier of the GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_self_link" {
  description = "Self-link URI of the GKE cluster."
  value       = google_container_cluster.primary.self_link
}

output "cluster_location" {
  description = "Region or location of the GKE cluster."
  value       = google_container_cluster.primary.location
}

output "cluster_region" {
  description = "Region of the GKE cluster."
  value       = var.region
}

output "cluster_endpoint" {
  description = "IP address of the GKE API server."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public certificate of the cluster CA."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_master_version" {
  description = "Current Kubernetes version of the control plane."
  value       = google_container_cluster.primary.master_version
}

output "workload_identity_pool" {
  description = "Workload Identity pool in the format {project}.svc.id.goog."
  value       = var.enable_workload_identity ? "${var.project_id}.svc.id.goog" : null
}

output "node_pool_names" {
  description = "Map of logical node-pool keys to created names."
  value       = { for key, pool in google_container_node_pool.pools : key => pool.name }
}

output "node_pool_ids" {
  description = "Map of logical node-pool keys to created IDs."
  value       = { for key, pool in google_container_node_pool.pools : key => pool.id }
}

output "get_credentials_command" {
  description = "gcloud command to configure kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --location=${google_container_cluster.primary.location} --project=${var.project_id}"
}
