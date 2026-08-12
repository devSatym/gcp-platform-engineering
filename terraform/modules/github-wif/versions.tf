# =============================================================================
# modules/github-wif/versions.tf
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
    # null_resource used for WIF pool/provider soft-delete lifecycle handling
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
