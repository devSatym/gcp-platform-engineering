# Module: `argocd-bootstrap`

> **Path:** `terraform/modules/argocd-bootstrap/`  
> **Called from:** `environments/dev/main.tf` → `module "argocd_bootstrap"`  
> **Phase:** 4 (GitOps Bootstrap)

---

## Files

| File | Purpose |
|------|---------|
| `main.tf` | ArgoCD Helm install + root app + WI IAM bindings |
| `providers.tf` | Required providers declaration (google, helm, null) |
| `variables.tf` | All inputs from GKE + service-accounts modules |
| `outputs.tf` | ArgoCD access commands |
| `values.yaml` | ArgoCD Helm chart values template |
| `root-application.yaml` | ArgoCD root Application manifest template |

---

## Design Philosophy

```
Terraform owns → GCP resources (VPC, GKE, IAM, Artifact Registry)
ArgoCD owns    → Everything inside Kubernetes (apps, config, operators)
```

This module is the **one-time bridge**. After it runs, Terraform never manages Kubernetes resources again.

---

## `providers.tf`

```hcl
terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
    helm   = { source = "hashicorp/helm",   version = "~> 2.12" }
    null   = { source = "hashicorp/null",   version = "~> 3.0" }
  }
}
```

**Why no `kubernetes` provider here:**  
The `kubernetes_manifest` resource requires a cluster connection during `terraform plan`. On first apply, the cluster doesn't exist yet → **"no client config" error**. Using `null_resource + local-exec` (kubectl) instead — runs only during `apply`, after the cluster is up.

---

## `main.tf` — Resources

### Resource 1: `helm_release "argocd"`

```hcl
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version   # Pinned to "7.7.10"

  wait    = true    # Wait for all ArgoCD pods to be Ready
  timeout = 600     # 10 min — accounts for slow image pulls on first install

  values = [
    templatefile("${path.module}/values.yaml", {
      project_id                = var.project_id
      argocd_sa_email           = var.argocd_sa_email
      external_secrets_sa_email = var.external_secrets_sa_email
      git_repo_url              = var.git_repo_url
    })
  ]
}
```

**Template variables injected into `values.yaml`:**
- `${argocd_sa_email}` → `serviceAccount.annotations.iam.gke.io/gcp-service-account` for `argocd-server` and `argocd-repo-server`
- `${git_repo_url}` → `configs.repositories.project-2.url`

**`wait = true`** ensures downstream `null_resource.root_application` can use the ArgoCD API immediately.

---

### Resource 2: `null_resource "root_application"`

```hcl
resource "null_resource" "root_application" {
  triggers = {
    manifest_hash    = sha256(templatefile("${path.module}/root-application.yaml", { git_repo_url = var.git_repo_url }))
    cluster_endpoint = var.cluster_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      export USE_GKE_GCLOUD_AUTH_PLUGIN=True

      # Authenticate kubectl
      gcloud container clusters get-credentials ${var.cluster_name} \
        --region=${var.cluster_region} \
        --project=${var.project_id}

      # Wait 30s for GKE API server to stabilize
      sleep 30

      # STEP 1: Apply AppProjects FIRST (chicken-and-egg fix)
      kubectl apply --server-side --force-conflicts --validate=false \
        -f "${path.module}/../../../gitops/bootstrap/projects.yaml"
      sleep 5

      # STEP 2: Apply root Application (App of Apps)
      cat <<'MANIFEST' | kubectl apply --validate=false -f -
      ${templatefile("${path.module}/root-application.yaml", { git_repo_url = var.git_repo_url })}
      MANIFEST
    EOT
  }

  depends_on = [helm_release.argocd]
}
```

**Two-step bootstrap order:**
1. `projects.yaml` first — ArgoCD rejects any `Application` whose `project:` field references a non-existent `AppProject`
2. `root-application.yaml` second — uses `project: default` (always exists) so it's safe after projects are created

**`triggers`:** The resource re-applies if the manifest template content changes OR the cluster endpoint changes.

**File reference:** `"${path.module}/../../../gitops/bootstrap/projects.yaml"` — the bootstrap module directly references the GitOps directory in the same repo. This is the Terraform→GitOps handoff point.

---

### Resource 3: `google_service_account_iam_member "argocd_wi"`

```hcl
resource "google_service_account_iam_member" "argocd_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.argocd_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-server]"
}
```

**What this does:** Allows the K8s SA `argocd-server` in the `argocd` namespace to impersonate `sa-argocd`.  
**Format:** `serviceAccount:{project}.svc.id.goog[{namespace}/{k8s-sa-name}]`

---

### Resource 4: `google_service_account_iam_member "argocd_repo_server_wi"`

```hcl
member = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-repo-server]"
```

Same as above but for the `argocd-repo-server` pod (separate SA, separate binding).

---

### Resource 5: `google_service_account_iam_member "external_secrets_wi"`

```hcl
resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.external_secrets_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[platform-system/external-secrets]"
}
```

Allows `external-secrets` K8s SA in `platform-system` namespace to impersonate `sa-external-secrets`.

---

## `values.yaml` — Key Sections

### Workload Identity annotations

```yaml
server:
  serviceAccount:
    name: argocd-server
    annotations:
      iam.gke.io/gcp-service-account: "${argocd_sa_email}"

repoServer:
  serviceAccount:
    name: argocd-repo-server
    annotations:
      iam.gke.io/gcp-service-account: "${argocd_sa_email}"
```

The annotation tells the GKE metadata server which GCP SA to exchange tokens for.

### Repository config

```yaml
configs:
  repositories:
    project-2:
      url: "${git_repo_url}"
      type: git
```

Registers the monorepo so ArgoCD can pull manifests. For public repos, no credentials needed.

### RBAC

```yaml
configs:
  rbac:
    policy.default: role:readonly
    policy.csv: |
      p, role:platform-admin, applications, *, */*, allow
      p, role:developer, applications, get, applications/*, allow
      g, admin, role:platform-admin
```

Three roles: `platform-admin` (full), `developer` (sync applications only), `observer` (read-only).

### Node scheduling

All ArgoCD components (`server`, `repoServer`, `controller`, `applicationSet`, `redis`) run on the **system node pool**:

```yaml
server:
  tolerations:
    - key: "workload"
      operator: "Equal"
      value: "system"
      effect: "NoSchedule"
  nodeSelector:
    workload: system
```

### Notifications

Pre-configured templates for sync-succeeded, sync-failed, health-degraded, deployed events. Triggers are defined, but subscriptions (Slack/email targets) need to be configured separately.

---

## `root-application.yaml` — App of Apps Entry Point

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"     # Root syncs before everything else
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # Deletes child apps when root is deleted
spec:
  project: default                           # Always exists — safe for bootstrap
  source:
    repoURL: "${git_repo_url}"
    targetRevision: main
    path: gitops/bootstrap                   # ArgoCD watches THIS directory
    directory:
      recurse: false                         # Explicit child app discovery
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true       # Remove resources deleted from Git
      selfHeal: true    # Revert manual kubectl changes
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**`path: gitops/bootstrap`** — this is the handoff. Once this Application is created, ArgoCD discovers and syncs everything in `gitops/bootstrap/` continuously from Git.

---

## `variables.tf` — All Inputs

| Variable | Source | Description |
|----------|--------|-------------|
| `project_id` | `var.project_id` | GCP project |
| `cluster_name` | `module.gke.cluster_name` | GKE cluster name |
| `cluster_endpoint` | `module.gke.cluster_endpoint` | API server IP (sensitive) |
| `cluster_ca_certificate` | `module.gke.cluster_ca_certificate` | CA cert (sensitive) |
| `cluster_region` | `module.gke.cluster_location` | GKE region |
| `argocd_sa_email` | `module.service_accounts.argocd_sa_email` | For WI binding + values.yaml |
| `external_secrets_sa_email` | `module.service_accounts.external_secrets_sa_email` | For WI binding |
| `argocd_chart_version` | default `"7.7.10"` | Pinned Helm chart version |
| `git_repo_url` | hardcoded in main.tf | No default — must be explicit |

---

## `outputs.tf`

| Output | Value | Usage |
|--------|-------|-------|
| `argocd_namespace` | `helm_release.argocd.namespace` | Verification |
| `argocd_chart_version` | `helm_release.argocd.version` | Verification |
| `argocd_access_command` | `kubectl port-forward svc/argocd-server -n argocd 8080:443` | Printed after apply |
| `argocd_password_command` | `kubectl -n argocd get secret argocd-initial-admin-secret ...` | Printed after apply |
