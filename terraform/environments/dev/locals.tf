# =============================================================================
# environments/dev/locals.tf
#
# Common labels applied to all resources in the dev environment.
# =============================================================================

locals {
  labels = {
    environment = var.environment
    team        = "platform"
    project     = "otel-demo"
    managed-by  = "terraform"
    owner       = "satyam"
  }
}
