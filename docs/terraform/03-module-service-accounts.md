# Module: `service-accounts`

> **Path:** `terraform/modules/service-accounts/`  
> **Called from:** `environments/dev/main.tf` → `module "service_accounts"`  
> **Phase:** 2 (Foundation)

---

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Creates 4 GCP SAs + all IAM role bindings |
| `variables.tf` | `project_id`, `labels` |
| `outputs.tf` | SA email outputs (consumed by gke, argocd-bootstrap, artifact-registry, github-wif) |

---

## `main.tf` — Resources

### `locals` block

```hcl
locals {
  sa_member = {
    gke_nodes        = "serviceAccount:${google_service_account.gke_nodes.email}"
    argocd           = "serviceAccount:${google_service_account.argocd.email}"
    external_secrets = "serviceAccount:${google_service_account.external_secrets.email}"
    github_actions   = "serviceAccount:${google_service_account.github_actions.email}"
  }
}
```

Used internally to avoid repeating `serviceAccount:${...email}` format in every IAM binding.

---

## Service Account 1: `sa-gke-nodes`

**Identity for:** All GKE node VMs (VM-level identity, not pod-level).

```hcl
resource "google_service_account" "gke_nodes" {
  account_id   = "sa-gke-nodes"
  display_name = "GKE Node Service Account"
}
```

### IAM Roles Granted

| Resource | Role | Why |
|----------|------|-----|
| `google_project_iam_member.gke_nodes_log_writer` | `roles/logging.logWriter` | Nodes write logs to Cloud Logging |
| `google_project_iam_member.gke_nodes_metric_writer` | `roles/monitoring.metricWriter` | Nodes write metrics to Cloud Monitoring |
| `google_project_iam_member.gke_nodes_monitoring_viewer` | `roles/monitoring.viewer` | Read monitoring data |
| `google_project_iam_member.gke_nodes_ar_reader` | `roles/artifactregistry.reader` | Pull container images from Artifact Registry |
| `google_project_iam_member.gke_nodes_metadata_writer` | `roles/stackdriver.resourceMetadata.writer` | Required for Workload Identity metadata server |

**Output:** `gke_node_sa_email`  
**Consumed by:**
- `module.gke` → `node_config.service_account` (all 3 node pools)
- `module.artifact_registry` → `gke_node_sa_email` (grants AR reader role at registry level)

---

## Service Account 2: `sa-argocd`

**Identity for:** ArgoCD server and repo-server pods (via Workload Identity).

```hcl
resource "google_service_account" "argocd" {
  account_id   = "sa-argocd"
  display_name = "ArgoCD Service Account"
}
```

### IAM Roles Granted

| Resource | Role | Why |
|----------|------|-----|
| `google_project_iam_member.argocd_secret_accessor` | `roles/secretmanager.secretAccessor` | ArgoCD reads secrets from Secret Manager |

**Output:** `argocd_sa_email`  
**Consumed by:**
- `module.gke` → `argocd_sa_email` → passed to `workload_identity.tf` for the WI binding (so GKE knows which K8s SA maps to this GCP SA)
- `module.argocd_bootstrap` → creates `google_service_account_iam_member` binding: `{project}.svc.id.goog[argocd/argocd-server]` → `sa-argocd`
- `argocd-bootstrap/values.yaml` → `serviceAccount.annotations.iam.gke.io/gcp-service-account`

---

## Service Account 3: `sa-external-secrets`

**Identity for:** External Secrets Operator (ESO) pod (via Workload Identity).

```hcl
resource "google_service_account" "external_secrets" {
  account_id   = "sa-external-secrets"
  display_name = "External Secrets Operator Service Account"
}
```

### IAM Roles Granted

| Resource | Role | Why |
|----------|------|-----|
| `google_project_iam_member.external_secrets_secret_accessor` | `roles/secretmanager.secretAccessor` | ESO reads secret values |
| `google_project_iam_member.external_secrets_secret_viewer` | `roles/secretmanager.viewer` | ESO lists/views secrets metadata |

**Output:** `external_secrets_sa_email`  
**Consumed by:**
- `module.argocd_bootstrap` → creates WI binding: `{project}.svc.id.goog[platform-system/external-secrets]` → `sa-external-secrets`
- `gitops/platform/external-secrets.yaml` → `serviceAccount.annotations.iam.gke.io/gcp-service-account`

---

## Service Account 4: `sa-github-actions`

**Identity for:** GitHub Actions CI/CD (via Workload Identity Federation — keyless).

```hcl
resource "google_service_account" "github_actions" {
  account_id   = "sa-github-actions"
  display_name = "GitHub Actions Service Account"
}
```

### IAM Roles Granted

| Resource | Role | Why |
|----------|------|-----|
| `google_project_iam_member.github_actions_ar_writer` | `roles/artifactregistry.writer` | Push Docker images to Artifact Registry |
| `google_project_iam_member.github_actions_gke_developer` | `roles/container.developer` | Run `gcloud container clusters get-credentials` |
| `google_project_iam_member.github_actions_token_creator` | `roles/iam.serviceAccountTokenCreator` | Create short-lived tokens for impersonation |

**Output:** `github_actions_sa_email`  
**Consumed by:**
- `module.artifact_registry` → grants `roles/artifactregistry.writer` at registry level (belt-and-suspenders)
- `module.github_wif` → creates the WIF IAM binding: `principalSet://iam.googleapis.com/{pool}/attribute.repository/{repo}` → `sa-github-actions`

---

## `outputs.tf` Summary

| Output | SA Email | Consumed By |
|--------|----------|-------------|
| `gke_node_sa_email` | `sa-gke-nodes@{project}.iam.gserviceaccount.com` | `module.gke`, `module.artifact_registry` |
| `gke_node_sa_name` | Full resource name | Informational |
| `argocd_sa_email` | `sa-argocd@{project}.iam.gserviceaccount.com` | `module.gke`, `module.argocd_bootstrap`, `values.yaml` |
| `external_secrets_sa_email` | `sa-external-secrets@{project}.iam.gserviceaccount.com` | `module.argocd_bootstrap`, `external-secrets.yaml` |
| `github_actions_sa_email` | `sa-github-actions@{project}.iam.gserviceaccount.com` | `module.artifact_registry`, `module.github_wif` |

---

## Note: `sa-terraform` Not Here

`sa-terraform` (the SA that runs Terraform itself) is created by `bootstrap/bootstrap.sh` — the chicken-and-egg problem: Terraform cannot create the SA it runs as.
