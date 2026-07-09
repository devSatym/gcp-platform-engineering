# =============================================================================
# environments/prod/outputs.tf
#
# Re-exports module outputs needed by Phase 3 (GKE) and later phases.
# These outputs are also useful for verification after terraform apply.
# =============================================================================

# ─── Networking ──────────────────────────────────────────────────────────────

output "project_id" {
  description = "GCP project ID."
  value       = var.project_id
}

output "region" {
  description = "GCP region."
  value       = var.region
}

output "vpc_name" {
  description = "Name of the platform VPC."
  value       = module.networking.vpc_name
}

output "vpc_self_link" {
  description = "Self-link of the platform VPC."
  value       = module.networking.vpc_self_link
}

output "gke_subnet_name" {
  description = "Name of the GKE node subnet — used in Phase 3 cluster config."
  value       = module.networking.gke_subnet_name
}

output "gke_subnet_self_link" {
  description = "Self-link of the GKE subnet — used in Phase 3 cluster resource."
  value       = module.networking.gke_subnet_self_link
}

output "gke_pods_range_name" {
  description = "Secondary IP range name for GKE pods — used in Phase 3 ip_allocation_policy."
  value       = module.networking.gke_pods_range_name
}

output "gke_services_range_name" {
  description = "Secondary IP range name for GKE services — used in Phase 3 ip_allocation_policy."
  value       = module.networking.gke_services_range_name
}

# ─── Cloud Router & NAT ──────────────────────────────────────────────────────

output "router_name" {
  description = "Name of the Cloud Router."
  value       = module.cloud_router.router_name
}

output "nat_name" {
  description = "Name of the Cloud NAT gateway."
  value       = module.nat.nat_name
}

# ─── Service Accounts ────────────────────────────────────────────────────────

output "gke_node_sa_email" {
  description = "GKE node SA email — used in Phase 3 node pool config."
  value       = module.service_accounts.gke_node_sa_email
}

output "argocd_sa_email" {
  description = "ArgoCD SA email — used in Phase 4 Workload Identity binding."
  value       = module.service_accounts.argocd_sa_email
}

output "external_secrets_sa_email" {
  description = "ESO SA email — used in Phase 4 Workload Identity binding."
  value       = module.service_accounts.external_secrets_sa_email
}

output "github_actions_sa_email" {
  description = "GitHub Actions SA email — used in Phase 6 WIF configuration."
  value       = module.service_accounts.github_actions_sa_email
}

# ─── Firewall ────────────────────────────────────────────────────────────────

output "firewall_rule_names" {
  description = "List of firewall rules created."
  value       = module.firewall.firewall_rule_names
}

# ─── GKE (Phase 3) ───────────────────────────────────────────────────────────

output "cluster_name" {
  description = "GKE cluster name."
  value       = module.gke.cluster_name
}

output "cluster_location" {
  description = "GKE cluster region."
  value       = module.gke.cluster_location
}

output "cluster_endpoint" {
  description = "GKE API server endpoint."
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded GKE cluster CA certificate."
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool — used for K8s SA → GCP SA bindings in Phase 4."
  value       = module.gke.workload_identity_pool
}

output "get_credentials_command" {
  description = "Run this to configure kubectl for the cluster."
  value       = module.gke.get_credentials_command
}

# ─── ArgoCD Bootstrap (Phase 4) ──────────────────────────────────────────────

output "argocd_access_command" {
  description = "kubectl port-forward command to access the ArgoCD UI."
  value       = module.argocd_bootstrap.argocd_access_command
}

output "argocd_password_command" {
  description = "Command to retrieve the initial ArgoCD admin password."
  value       = module.argocd_bootstrap.argocd_password_command
}

# ─── Artifact Registry (Phase 5) ─────────────────────────────────────────────

output "registry_url" {
  description = "Docker registry URL. Use as image prefix: {registry_url}/{image}:{tag}"
  value       = module.artifact_registry.registry_url
}

output "docker_auth_command" {
  description = "Run once to authenticate Docker for pushing images to Artifact Registry."
  value       = module.artifact_registry.docker_auth_command
}

# ─── GitHub WIF (Phase 6) ─────────────────────────────────────────────────────

output "wif_provider" {
  description = "WIF provider name. Set as GCP_WIF_PROVIDER GitHub Actions variable."
  value       = module.github_wif.workload_identity_provider
}

output "github_actions_sa_email_wif" {
  description = "SA email for GitHub Actions WIF. Set as GCP_SA_EMAIL GitHub Actions variable."
  value       = module.github_wif.github_actions_sa_email
}

