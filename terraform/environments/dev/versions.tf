# =============================================================================
# environments/dev/versions.tf
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    # Required by argocd-bootstrap module (helm_release)
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    # Required by argocd-bootstrap module (null_resource for root Application)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Provider configuration — uses Application Default Credentials (ADC).
# In CI: ADC is set via Workload Identity Federation (Phase 6).
# Locally: run `gcloud auth application-default login` or set
# GOOGLE_APPLICATION_CREDENTIALS to the sa-terraform key path.
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Fetches a short-lived OAuth2 access token from Application Default Credentials.
# Used by the helm and kubernetes providers to authenticate to GKE.
data "google_client_config" "default" {}

# Helm provider — authenticates to GKE using cluster outputs.
# The cluster endpoint and CA cert come from the gke module after it is applied.
# This avoids the "no client config" error on first plan when the cluster doesn't exist yet.
provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}
