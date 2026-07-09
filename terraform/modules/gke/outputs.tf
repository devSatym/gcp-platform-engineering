# =============================================================================
# modules/gke/outputs.tf
#
# Outputs consumed by:
#   Phase 4 (ArgoCD): cluster_name, cluster_endpoint, cluster_ca_certificate
#   Phase 5 (Helm/ArgoCD): cluster_name, cluster_location
#   Phase 6 (GitHub Actions): cluster_name for kubectl auth
#   kubeconfig: cluster_name, cluster_endpoint, cluster_ca_certificate
# =============================================================================

output "cluster_name" {
  description = "Name of the GKE cluster (e.g. otel-dev-gke)."
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
  description = "Region (location) of the GKE cluster."
  value       = google_container_cluster.primary.location
}

output "cluster_endpoint" {
  description = "IP address of the GKE API server. Required for kubectl and Helm."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true # Endpoint combined with CA cert and token provides full cluster access
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public certificate of the cluster CA. Used by kubectl and Helm providers."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_master_version" {
  description = "Current Kubernetes version of the GKE control plane."
  value       = google_container_cluster.primary.master_version
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this cluster. Format: {project}.svc.id.goog"
  value       = "${var.project_id}.svc.id.goog"
}

# ─── Node Pool Outputs ────────────────────────────────────────────────────────

output "system_pool_name" {
  description = "Name of the system node pool."
  value       = google_container_node_pool.system.name
}

output "general_pool_name" {
  description = "Name of the general node pool."
  value       = google_container_node_pool.general.name
}

output "spot_pool_name" {
  description = "Name of the spot node pool."
  value       = google_container_node_pool.spot.name
}

# ─── kubeconfig helper ────────────────────────────────────────────────────────

output "get_credentials_command" {
  description = "gcloud command to configure kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region=${google_container_cluster.primary.location} --project=${var.project_id}"
}
