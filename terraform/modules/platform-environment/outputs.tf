output "project_id" {
  description = "GCP project hosting this platform environment."
  value       = var.config.project_id
}

output "environment" {
  description = "Logical environment represented by this composition."
  value       = var.config.environment
}

output "region" {
  description = "Primary region for the environment."
  value       = var.config.region
}

output "vpc_name" {
  description = "Platform VPC name."
  value       = module.networking.vpc_name
}

output "gke_subnet_name" {
  description = "GKE node subnet name."
  value       = module.networking.gke_subnet_name
}

output "router_name" {
  description = "Cloud Router name."
  value       = module.cloud_router.router_name
}

output "nat_name" {
  description = "Cloud NAT name."
  value       = module.nat.nat_name
}

output "firewall_rule_names" {
  description = "Firewall rules created for the environment."
  value       = module.firewall.firewall_rule_names
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = module.gke.cluster_name
}

output "cluster_location" {
  description = "GKE cluster location."
  value       = module.gke.cluster_location
}

output "cluster_endpoint" {
  description = "GKE API endpoint."
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded GKE cluster CA certificate."
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "GKE Workload Identity pool."
  value       = module.gke.workload_identity_pool
}

output "gke_node_sa_email" {
  description = "GKE node service account email."
  value       = module.service_accounts.gke_node_sa_email
}

output "argocd_sa_email" {
  description = "ArgoCD Google service account email."
  value       = module.service_accounts.argocd_sa_email
}

output "external_secrets_sa_email" {
  description = "External Secrets Google service account email."
  value       = module.service_accounts.external_secrets_sa_email
}

output "github_actions_sa_email" {
  description = "GitHub Actions Google service account email."
  value       = module.service_accounts.github_actions_sa_email
}

output "registry_url" {
  description = "Artifact Registry Docker repository URL."
  value       = module.artifact_registry.registry_url
}

output "wif_provider" {
  description = "GitHub Workload Identity Federation provider."
  value       = module.github_wif.workload_identity_provider
}
