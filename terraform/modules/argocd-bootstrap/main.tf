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

  # The pinned Argo CD chart renders a large manifest. Avoid a second OpenAPI
  # schema download during bootstrap, which can time out before Helm creates
  # the release resources on a newly reachable GKE control plane.
  disable_openapi_validation = true

  # Include chart Jobs in readiness. The Argo CD chart uses a pre-install Job
  # to initialize its Redis credentials.
  wait_for_jobs = true

  # A failed install or upgrade must not leave the Helm release in a pending
  # state that blocks subsequent Terraform applies.
  atomic = true

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
# kubernetes_manifest cannot be used here because it tries to connect to the
# cluster during `terraform plan` — before the cluster exists.
# null_resource + local-exec only runs during `terraform apply`, after the GKE
# cluster and ArgoCD helm_release are fully up.
resource "null_resource" "root_application" {
  triggers = {
    # Re-apply if the manifest template content changes
    manifest_hash = sha256(templatefile("${path.module}/root-application.yaml", {
      git_repo_url = var.git_repo_url
    }))
    cluster_endpoint = var.cluster_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Required by newer gcloud versions for kubectl auth
      export USE_GKE_GCLOUD_AUTH_PLUGIN=True

      # Authenticate kubectl to the GKE cluster
      gcloud container clusters get-credentials ${var.cluster_name} \
        --location=${var.cluster_location} \
        --project=${var.project_id}

      # Wait for the GKE API server to fully accept connections.
      # The cluster endpoint takes ~30s after Helm install before it reliably
      # responds to kubectl — this prevents TLS handshake timeout errors.
      echo "Waiting 30s for Kubernetes API server to be ready..."
      sleep 30

      # STEP 1: Apply AppProjects FIRST (breaks the bootstrap chicken-and-egg).
      # ArgoCD rejects any Application whose project doesn't exist yet.
      # projects.yaml defines the bootstrap, platform, and workloads ownership boundaries.
      echo "Applying ArgoCD AppProjects..."
      kubectl apply --server-side --force-conflicts --validate=false \
        -f "${path.module}/../../../gitops/projects/projects.yaml"
      echo "Waiting for AppProjects to be registered..."
      sleep 5

      # STEP 2: Apply the root Application (App of Apps).
      # Root app uses project: default (always exists). Child apps discovered
      # by ArgoCD from gitops/bootstrap/ will reference their proper projects.
      echo "Applying root ArgoCD Application..."
      cat <<'MANIFEST' | kubectl apply --validate=false -f -
${templatefile("${path.module}/root-application.yaml", {
    git_repo_url = var.git_repo_url
})}
MANIFEST
    EOT
}

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
