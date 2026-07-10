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
      set -e

      # Required by newer gcloud versions for kubectl auth
      export USE_GKE_GCLOUD_AUTH_PLUGIN=True

      # Authenticate kubectl to the GKE cluster
      gcloud container clusters get-credentials ${var.cluster_name} \
        --region=${var.cluster_region} \
        --project=${var.project_id}

      # ── Wait for the API server to be reachable ──────────────────────────────
      # GKE clusters take ~30s after provisioning before the API server accepts
      # connections. kubectl apply immediately after helm install can hit TLS
      # handshake timeouts. This loop retries until kubectl can list namespaces.
      echo "Waiting for Kubernetes API server to be ready..."
      MAX_WAIT=300  # 5 minutes max
      ELAPSED=0
      until kubectl get namespaces --request-timeout=10s >/dev/null 2>&1; do
        if [ $ELAPSED -ge $MAX_WAIT ]; then
          echo "ERROR: API server did not become ready within $MAX_WAIT seconds"
          exit 1
        fi
        echo "  API server not ready yet (${ELAPSED}s elapsed) — retrying in 15s..."
        sleep 15
        ELAPSED=$((ELAPSED + 15))
      done
      echo "API server is ready (${ELAPSED}s elapsed)."

      # ── STEP 1: Apply AppProjects with retry ─────────────────────────────────
      # ArgoCD rejects any Application whose project doesn't exist yet.
      # projects.yaml defines: platform, applications, observability, networking, security.
      echo "Applying ArgoCD AppProjects..."
      RETRY=0
      MAX_RETRIES=5
      until kubectl apply --server-side --force-conflicts --validate=false \
          -f "${path.module}/../../../gitops/bootstrap/projects.yaml"; do
        RETRY=$((RETRY + 1))
        if [ $RETRY -ge $MAX_RETRIES ]; then
          echo "ERROR: Failed to apply AppProjects after $MAX_RETRIES attempts"
          exit 1
        fi
        echo "  kubectl apply failed (attempt $RETRY/$MAX_RETRIES) — retrying in 10s..."
        sleep 10
      done
      echo "AppProjects applied successfully."
      echo "Waiting 5s for AppProjects to be registered..."
      sleep 5

      # ── STEP 2: Apply the root Application (App of Apps) with retry ──────────
      # Root app uses project: default (always exists in ArgoCD).
      echo "Applying root ArgoCD Application..."
      RETRY=0
      until cat <<'MANIFEST' | kubectl apply --validate=false -f -
${templatefile("${path.module}/root-application.yaml", {
  git_repo_url = var.git_repo_url
})}
MANIFEST
      do
        RETRY=$((RETRY + 1))
        if [ $RETRY -ge $MAX_RETRIES ]; then
          echo "ERROR: Failed to apply root Application after $MAX_RETRIES attempts"
          exit 1
        fi
        echo "  kubectl apply failed (attempt $RETRY/$MAX_RETRIES) — retrying in 10s..."
        sleep 10
      done
      echo "Root Application applied successfully."
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
