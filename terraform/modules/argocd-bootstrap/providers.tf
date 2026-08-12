# =============================================================================
# modules/argocd-bootstrap/providers.tf
#
# Declares the providers this module requires.
#
# NOTE: Provider *configuration* (host, credentials, etc.) is NOT done here.
# Child modules must not configure providers — only the root module does.
# The root module passes helm/null providers down to this module implicitly.
#
# NOTE: The kubernetes provider was removed. The root ArgoCD Application is
# now applied via null_resource + local-exec (kubectl apply) instead of
# kubernetes_manifest. This avoids the "no client config" plan-time error
# that occurs when the cluster doesn't exist yet on first apply.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    # null_resource applies the ArgoCD root Application via kubectl during apply
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}


