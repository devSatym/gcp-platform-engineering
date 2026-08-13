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
locals {
  # A Terraform apply must report success only after the GitOps revision it
  # bootstraps has converged. Hash every GitOps input so a later apply also
  # re-runs the read-only readiness check when platform configuration changes.
  gitops_root       = abspath("${path.module}/../../../gitops")
  gitops_configured = sort(fileset(local.gitops_root, "**"))
  gitops_config_hash = sha256(join("", [
    for file in local.gitops_configured : "${file}:${filesha256("${local.gitops_root}/${file}")}"
  ]))
}

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

      # Wait for the GKE API server to fully accept connections. A probe is
      # deterministic; a fixed sleep can be too short on a fresh control plane
      # and unnecessarily slow on a warm one.
      echo "Waiting for the Kubernetes API server to be ready..."
      for attempt in $(seq 1 60); do
        if kubectl version --request-timeout=10s >/dev/null 2>&1; then
          break
        fi
        if [ "$${attempt}" -eq 60 ]; then
          echo "Kubernetes API did not become ready within five minutes." >&2
          exit 1
        fi
        sleep 5
      done

      # STEP 1: Apply AppProjects FIRST (breaks the bootstrap chicken-and-egg).
      # ArgoCD rejects any Application whose project doesn't exist yet.
      # projects.yaml defines the bootstrap, platform, and workloads ownership boundaries.
      echo "Applying ArgoCD AppProjects..."
      kubectl apply --server-side --force-conflicts --validate=false \
        -f "${path.module}/../../../gitops/projects/projects.yaml"
      for attempt in $(seq 1 30); do
        if kubectl -n argocd get appproject platform >/dev/null 2>&1 && \
          kubectl -n argocd get appproject workloads >/dev/null 2>&1; then
          break
        fi
        if [ "$${attempt}" -eq 30 ]; then
          echo "Argo CD AppProjects were not registered within 150 seconds." >&2
          exit 1
        fi
        sleep 5
      done

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

depends_on = [
  helm_release.argocd,
  google_service_account_iam_member.argocd_wi,
  google_service_account_iam_member.argocd_repo_server_wi,
  google_service_account_iam_member.external_secrets_wi,
]
}

# The final bootstrap gate is deliberately read-only. It makes a successful
# Terraform apply meaningful: all Applications generated from GitOps contracts
# have reached Synced/Healthy, including the observability dashboard check.
resource "null_resource" "gitops_convergence" {
  triggers = {
    root_application_id = null_resource.root_application.id
    gitops_config_hash  = local.gitops_config_hash
    environment         = var.environment
  }

  provisioner "local-exec" {
    command = "bash '${path.module}/../../../scripts/wait-for-gitops-convergence.sh' --environment '${var.environment}' --timeout '${var.gitops_ready_timeout_seconds}'"
  }

  depends_on = [null_resource.root_application]
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
