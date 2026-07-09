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
