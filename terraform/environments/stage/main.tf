# =============================================================================
# environments/stage/main.tf — Stage environment
# Identical module composition to dev/ — environment differences come from tfvars.
# =============================================================================

module "project" {
  source     = "../../modules/project"
  project_id = var.project_id
  labels     = local.labels
}

module "networking" {
  source     = "../../modules/networking"
  project_id = var.project_id
  region     = var.region
  labels     = local.labels
  depends_on = [module.project]
}

module "cloud_router" {
  source     = "../../modules/cloud-router"
  project_id = var.project_id
  region     = var.region
  vpc_name   = module.networking.vpc_name
  depends_on = [module.networking]
}

module "nat" {
  source      = "../../modules/nat"
  project_id  = var.project_id
  region      = var.region
  router_name = module.cloud_router.router_name
  depends_on  = [module.cloud_router]
}

module "firewall" {
  source     = "../../modules/firewall"
  project_id = var.project_id
  vpc_name   = module.networking.vpc_name
  depends_on = [module.networking]
}

module "service_accounts" {
  source     = "../../modules/service-accounts"
  project_id = var.project_id
  labels     = local.labels
  depends_on = [module.project]
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. GKE — Private regional cluster (Phase 3)
# Stage: same pool sizing as dev; could be increased when load testing begins.
# ─────────────────────────────────────────────────────────────────────────────
module "gke" {
  source     = "../../modules/gke"
  project_id = var.project_id
  region     = var.region
  labels     = local.labels

  cluster_name            = "otel-${var.environment}-gke"
  vpc_name                = module.networking.vpc_name
  gke_subnet_name         = module.networking.gke_subnet_name
  gke_pods_range_name     = module.networking.gke_pods_range_name
  gke_services_range_name = module.networking.gke_services_range_name
  gke_node_sa_email       = module.service_accounts.gke_node_sa_email

  # Workload Identity bindings (Phase 4)
  argocd_sa_email           = module.service_accounts.argocd_sa_email
  external_secrets_sa_email = module.service_accounts.external_secrets_sa_email

  system_pool_min_count     = 1
  system_pool_max_count     = 2
  general_pool_min_count    = 1
  general_pool_max_count    = 4
  spot_pool_min_count       = 0
  spot_pool_max_count       = 2

  enable_private_endpoint = false          # Restrict further when VPN is available
  master_authorized_cidr  = "0.0.0.0/0"

  depends_on_nat = module.nat.nat_name
  depends_on     = [module.networking, module.service_accounts, module.nat]
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. ArgoCD Bootstrap — GitOps controller (Phase 4)
# ─────────────────────────────────────────────────────────────────────────────
module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  project_id                = var.project_id
  cluster_name              = module.gke.cluster_name
  cluster_endpoint          = module.gke.cluster_endpoint
  cluster_ca_certificate    = module.gke.cluster_ca_certificate
  cluster_region            = module.gke.cluster_location
  argocd_sa_email           = module.service_accounts.argocd_sa_email
  external_secrets_sa_email = module.service_accounts.external_secrets_sa_email

  # !! UPDATE THIS to your actual GitHub repo URL !!
  git_repo_url = "https://github.com/YOUR_USERNAME/project-2.git"

  depends_on = [module.gke]
}

# ─────────────────────────────────────────────────────────────────────────────
# 9. Artifact Registry — Private Docker registry for container images (Phase 5)
# GKE nodes get pull access; GitHub Actions gets push access (used in Phase 6).
# ─────────────────────────────────────────────────────────────────────────────
module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id              = var.project_id
  region                  = var.region
  gke_node_sa_email       = module.service_accounts.gke_node_sa_email
  github_actions_sa_email = module.service_accounts.github_actions_sa_email
  labels                  = local.labels

  depends_on = [module.project]
}

# ─────────────────────────────────────────────────────────────────────────────
# 10. GitHub Workload Identity Federation (Phase 6)
# Allows GitHub Actions to authenticate to GCP without JSON keys.
# After this runs: set GCP_WIF_PROVIDER and GCP_SA_EMAIL as GitHub Actions variables.
# ─────────────────────────────────────────────────────────────────────────────
module "github_wif" {
  source = "../../modules/github-wif"

  project_id              = var.project_id
  # !! UPDATE THIS to your GitHub repo in owner/repo format !!
  github_repo             = "YOUR_USERNAME/project-2"
  github_actions_sa_email = module.service_accounts.github_actions_sa_email

  depends_on = [module.project]
}
