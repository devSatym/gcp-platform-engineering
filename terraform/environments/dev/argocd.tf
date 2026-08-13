data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${module.platform.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.platform.cluster_ca_certificate)
  }
}

module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  project_id                = var.platform_config.project_id
  cluster_name              = module.platform.cluster_name
  cluster_endpoint          = module.platform.cluster_endpoint
  cluster_ca_certificate    = module.platform.cluster_ca_certificate
  cluster_location          = module.platform.cluster_location
  environment               = var.platform_config.environment
  argocd_sa_email           = module.platform.argocd_sa_email
  external_secrets_sa_email = module.platform.external_secrets_sa_email
  argocd_chart_version      = var.platform_config.argocd.chart_version
  git_repo_url              = var.platform_config.argocd.git_repo_url
}

output "argocd_access_command" {
  description = "Command to port-forward the ArgoCD UI."
  value       = module.argocd_bootstrap.argocd_access_command
}

output "argocd_password_command" {
  description = "Command to retrieve the initial ArgoCD password."
  value       = module.argocd_bootstrap.argocd_password_command
}
