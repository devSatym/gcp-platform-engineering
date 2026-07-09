# =============================================================================
# modules/project/main.tf
#
# Enables all required GCP APIs for the platform.
# Must be applied before any other module — all resources depend on APIs.
# =============================================================================

locals {
  # All APIs required across all phases.
  # Grouped by phase for clarity; all are enabled together.
  apis = toset([
    # Phase 2 — Networking
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",

    # Phase 3 — GKE
    "container.googleapis.com",

    # Phase 5 — Applications
    "artifactregistry.googleapis.com",
    "dns.googleapis.com",

    # Phase 6 — Security / Secrets
    "secretmanager.googleapis.com",

    # Phase 7 — Security Platform
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "containerscanning.googleapis.com",

    # Phase 8 — Observability
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",

    # Phase 14 — Backup
    "gkebackup.googleapis.com",
  ])
}

resource "google_project_service" "apis" {
  for_each = local.apis

  project = var.project_id
  service = each.value

  # Never disable APIs on terraform destroy — other resources may depend on them
  # and re-enabling takes time during the next apply.
  disable_on_destroy = false
}
