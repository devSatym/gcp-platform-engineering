# =============================================================================
# modules/artifact-registry/main.tf
#
# Creates a Docker Artifact Registry repository for the platform.
# GKE nodes are granted read access so they can pull images without
# additional authentication configuration.
#
# Image strategy:
#   Phase 5: GKE pulls from upstream public registries (ghcr.io/open-telemetry)
#   Phase 6: GitHub Actions mirrors images here using image tags based on Git SHA
#   Phase 7: Images are signed via Cosign and Binary Authorization enforces signing
#
# Benefits of Artifact Registry over Docker Hub / ghcr.io:
#   - Private images — no public exposure
#   - Co-located with asia-south1 cluster — faster pulls, no egress cost
#   - Vulnerability scanning built in
#   - Lifecycle policies prevent unbounded storage growth
#   - Easier Binary Authorization integration (Phase 7)
# =============================================================================

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  format        = "DOCKER"
  description   = "Docker container images for the platform (OTel Demo, custom builds)"

  # Lifecycle policy — keep the last 10 versions of each image to prevent
  # unbounded storage growth while preserving recent rollback capability.
  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-last-10-tagged"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state = "UNTAGGED"
    }
  }

  labels = var.labels
}

# ─────────────────────────────────────────────────────────────────────────────
# GKE Node SA — Artifact Registry Reader
# GKE nodes pull container images using the node SA (sa-gke-nodes).
# The reader role allows pulling but not pushing — least privilege.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_artifact_registry_repository_iam_member" "gke_node_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.docker.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.gke_node_sa_email}"
}

# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions SA — Artifact Registry Writer (Phase 6)
# CI/CD pipeline pushes built images. Writer role allows push + pull.
# Binding is created now so Phase 6 CI/CD works without Terraform changes.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_artifact_registry_repository_iam_member" "github_actions_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.docker.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.github_actions_sa_email}"
}
