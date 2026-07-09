# =============================================================================
# environments/dev/backend.tf
#
# Remote state configuration — GCS backend.
# UPDATE: Set bucket to your actual Terraform state bucket name.
# Run bootstrap/bootstrap.sh first to create the bucket.
# =============================================================================

terraform {
  backend "gcs" {
    # !! UPDATE THIS: replace with your actual GCS bucket name !!
    # Format: {project_id}-tf-state
    bucket = "platform-engineering-demo-tf-state"

    # State file path within the bucket — unique per environment
    prefix = "dev/foundation"
  }
}
