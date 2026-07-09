# =============================================================================
# modules/argocd-bootstrap/providers.tf
#
# Configures the Kubernetes and Helm providers to authenticate against the GKE
# cluster that was created in Phase 3.
#
# Authentication uses the gcloud CLI (Application Default Credentials).
# This works both locally (after gcloud auth application-default login) and
# in CI (via Workload Identity Federation in Phase 6).
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Helm provider — connects to the GKE cluster
# ─────────────────────────────────────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = "https://${var.cluster_endpoint}"
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

    # Use gcloud exec to get an access token.
    # This avoids storing static credentials and works with ADC.
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gcloud"
      args = [
        "container",
        "clusters",
        "get-credentials",
        var.cluster_name,
        "--region", var.cluster_region,
        "--project", var.project_id,
        "--quiet",
      ]
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes provider — for applying the root Application manifest
# ─────────────────────────────────────────────────────────────────────────────
provider "kubernetes" {
  host                   = "https://${var.cluster_endpoint}"
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gcloud"
    args = [
      "container",
      "clusters",
      "get-credentials",
      var.cluster_name,
      "--region", var.cluster_region,
      "--project", var.project_id,
      "--quiet",
    ]
  }
}
