# =============================================================================
# modules/argocd-bootstrap/main.tf
#
# The ONE-TIME bridge between Terraform and ArgoCD.
#
# This module is the last Terraform-managed Kubernetes resource.
# After this runs, ArgoCD owns everything inside Kubernetes.
# Terraform owns cloud infrastructure. ArgoCD owns K8s applications.
#
# Separation of concerns:
#   Terraform → GCP resources (VPC, GKE, IAM, Artifact Registry)
#   ArgoCD    → Everything inside Kubernetes (apps, config, operators)
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# ARGOCD — Installed via official Helm chart
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version # Pinned — prevents surprise breaking changes

  # wait=true: Terraform waits for all ArgoCD pods to be Ready before marking
  # this resource as complete. This ensures downstream resources (root app) can
  # use the ArgoCD API immediately after apply.
  wait    = true
  timeout = 600 # 10 minutes — allow time for image pulls on first install

  values = [
    templatefile("${path.module}/values.yaml", {
      project_id                = var.project_id
      argocd_sa_email           = var.argocd_sa_email
      external_secrets_sa_email = var.external_secrets_sa_email
      git_repo_url              = var.git_repo_url
    })
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# ROOT APPLICATION — Applied after ArgoCD is running
# This is the App of Apps entry point. ArgoCD watches gitops/bootstrap/
# and discovers all child applications from there.
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_manifest" "root_application" {
  manifest = yamldecode(templatefile("${path.module}/root-application.yaml", {
    git_repo_url = var.git_repo_url
  }))

  depends_on = [helm_release.argocd]
}

# ─────────────────────────────────────────────────────────────────────────────
# WORKLOAD IDENTITY — ArgoCD K8s SA → GCP SA binding
# Allows the argocd-server pod to call GCP Secret Manager without JSON keys.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account_iam_member" "argocd_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.argocd_sa_email}"
  role               = "roles/iam.workloadIdentityUser"

  # Format: serviceAccount:{project}.svc.id.goog[{namespace}/{k8s-sa-name}]
  member = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-server]"
}

resource "google_service_account_iam_member" "argocd_repo_server_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.argocd_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-repo-server]"
}

# ─────────────────────────────────────────────────────────────────────────────
# WORKLOAD IDENTITY — External Secrets Operator K8s SA → GCP SA binding
# ESO reads secrets from GCP Secret Manager into K8s Secrets.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.external_secrets_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[platform-system/external-secrets]"
}
