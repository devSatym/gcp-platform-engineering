# =============================================================================
# environments/dev/main.tf
#
# Dev environment — composes Phase 2 (networking) and Phase 3 (GKE) modules.
# Module call order matches the dependency graph in docs/architecture/terraform-dependency-graph.md
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# 1. Project — Enable APIs (must run first)
# ─────────────────────────────────────────────────────────────────────────────
module "project" {
  source     = "../../modules/project"
  project_id = var.project_id
  labels     = local.labels
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Networking — VPC, subnets, secondary ranges
# ─────────────────────────────────────────────────────────────────────────────
module "networking" {
  source     = "../../modules/networking"
  project_id = var.project_id
  region     = var.region
  labels     = local.labels

  # IP plan values (defaults match the plan; override in tfvars if needed)
  gke_subnet_cidr        = "10.0.0.0/20"
  management_subnet_cidr = "10.0.16.0/24"
  proxy_subnet_cidr      = "10.0.17.0/24"
  gke_pods_cidr          = "10.10.0.0/16"
  gke_services_cidr      = "10.20.0.0/20"

  depends_on = [module.project]
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Cloud Router — prerequisite for NAT
# ─────────────────────────────────────────────────────────────────────────────
module "cloud_router" {
  source     = "../../modules/cloud-router"
  project_id = var.project_id
  region     = var.region
  vpc_name   = module.networking.vpc_name

  depends_on = [module.networking]
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Cloud NAT — outbound internet for private nodes
# ─────────────────────────────────────────────────────────────────────────────
module "nat" {
  source      = "../../modules/nat"
  project_id  = var.project_id
  region      = var.region
  router_name = module.cloud_router.router_name

  depends_on = [module.cloud_router]
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Firewall — least-privilege ingress rules
# ─────────────────────────────────────────────────────────────────────────────
module "firewall" {
  source        = "../../modules/firewall"
  project_id    = var.project_id
  vpc_name      = module.networking.vpc_name
  internal_cidr = "10.0.0.0/16"

  depends_on = [module.networking]
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Service Accounts — dedicated SAs with least-privilege IAM
# ─────────────────────────────────────────────────────────────────────────────
module "service_accounts" {
  source     = "../../modules/service-accounts"
  project_id = var.project_id
  labels     = local.labels

  depends_on = [module.project]
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. GKE — Private regional cluster with 3 node pools (Phase 3)
# Dev: smaller pools, public API endpoint for easy local kubectl access.
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

  # Workload Identity bindings (Phase 4) — passed to workload_identity.tf
  argocd_sa_email           = module.service_accounts.argocd_sa_email
  external_secrets_sa_email = module.service_accounts.external_secrets_sa_email

  # ── All sizes come from local.sizing in locals.tf — change there, not here ──
  system_pool_machine_type  = local.sizing.system_machine_type
  system_pool_min_count     = local.sizing.system_min_count
  system_pool_max_count     = local.sizing.system_max_count

  general_pool_machine_type = local.sizing.general_machine_type
  general_pool_min_count    = local.sizing.general_min_count
  general_pool_max_count    = local.sizing.general_max_count

  spot_pool_machine_type    = local.sizing.spot_machine_type
  spot_pool_min_count       = local.sizing.spot_min_count
  spot_pool_max_count       = local.sizing.spot_max_count

  # Dev: public API endpoint — allows kubectl from local machine.
  # Prod: set enable_private_endpoint=true, master_authorized_cidr to VPN CIDR.
  enable_private_endpoint = false
  master_authorized_cidr  = "0.0.0.0/0"

  # NAT must be up before GKE — private nodes need it to pull images.
  depends_on_nat = module.nat.nat_name

  depends_on = [module.networking, module.service_accounts, module.nat]
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. ArgoCD Bootstrap — GitOps controller one-time installation (Phase 4)
# After this runs, Terraform never manages Kubernetes resources again.
# ArgoCD watches gitops/ and reconciles the cluster continuously from Git.
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

  git_repo_url = "https://github.com/devSatym/gcp-platform-engineering.git"

  # IMPORTANT: depends_on = [module.gke] is required here.
  # The WI IAM bindings in argocd-bootstrap use the member format:
  #   serviceAccount:{project}.svc.id.goog[namespace/sa]
  # The identity pool ({project}.svc.id.goog) is only created AFTER the GKE
  # cluster with workload_identity_config is fully provisioned.
  # Without this, Terraform runs WI bindings in parallel with cluster creation
  # and gets: "Identity Pool does not exist" error 400.
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
  github_repo             = "devSatym/gcp-platform-engineering"
  github_actions_sa_email = module.service_accounts.github_actions_sa_email

  depends_on = [module.project]
}
