# =============================================================================
# modules/service-accounts/main.tf
#
# Creates dedicated service accounts for each platform component.
# Each SA gets only the minimum IAM roles it needs — no broad roles like Editor.
#
# Service accounts created:
#   sa-gke-nodes        — identity for GKE node VMs
#   sa-argocd           — Workload Identity for ArgoCD (Phase 4)
#   sa-external-secrets — Workload Identity for External Secrets Operator (Phase 4)
#   sa-github-actions   — Workload Identity Federation for GitHub Actions CI (Phase 6)
#
# Note: sa-terraform is created by bootstrap.sh (chicken-and-egg problem).
# =============================================================================

locals {
  # Reusable: full project member format
  sa_member = {
    gke_nodes        = "serviceAccount:${google_service_account.gke_nodes.email}"
    argocd           = "serviceAccount:${google_service_account.argocd.email}"
    external_secrets = "serviceAccount:${google_service_account.external_secrets.email}"
    github_actions   = "serviceAccount:${google_service_account.github_actions.email}"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# GKE Node Service Account
# Used by all GKE node VMs as their VM identity.
# Must have logging + monitoring write access plus read access to Artifact Registry.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "sa-gke-nodes"
  display_name = "GKE Node Service Account"
  description  = "Identity for GKE node VMs. Grants log/metric write and AR read."
}

resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.sa_member.gke_nodes
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = local.sa_member.gke_nodes
}

resource "google_project_iam_member" "gke_nodes_ar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = local.sa_member.gke_nodes
}

resource "google_project_iam_member" "gke_nodes_metadata_writer" {
  project = var.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = local.sa_member.gke_nodes
}

# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD Service Account
# Used via Workload Identity (Phase 4) to allow ArgoCD to read secrets.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account" "argocd" {
  project      = var.project_id
  account_id   = "sa-argocd"
  display_name = "ArgoCD Service Account"
  description  = "Workload Identity SA for ArgoCD. Access to Secret Manager for ArgoCD secrets."
}

# ─────────────────────────────────────────────────────────────────────────────
# External Secrets Operator Service Account
# ESO reads from Secret Manager and syncs secrets into Kubernetes.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account" "external_secrets" {
  project      = var.project_id
  account_id   = "sa-external-secrets"
  display_name = "External Secrets Operator Service Account"
  description  = "Workload Identity SA for ESO. Read-only access to Secret Manager."
}

resource "google_secret_manager_secret_iam_member" "external_secrets_secret_accessor" {
  for_each  = var.secret_ids
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_member.external_secrets
}

# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions Service Account
# Used via Workload Identity Federation (keyless) in Phase 6.
# Needs to push images to Artifact Registry and read GKE cluster info.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account" "github_actions" {
  project      = var.project_id
  account_id   = "sa-github-actions"
  display_name = "GitHub Actions Service Account"
  description  = "Impersonated by GitHub Actions via Workload Identity Federation for CI/CD. Pushes images to Artifact Registry."
}

resource "google_project_iam_member" "github_actions_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = local.sa_member.github_actions
}

# The post-deploy verification workflow only reads cluster state. This role
# permits it to obtain credentials and inspect the Kubernetes API without
# granting deployment or infrastructure mutation permissions.
resource "google_project_iam_member" "github_actions_gke_viewer" {
  project = var.project_id
  role    = "roles/container.viewer"
  member  = local.sa_member.github_actions
}
