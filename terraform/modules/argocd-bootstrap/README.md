# Module: argocd-bootstrap

Installs ArgoCD into the GKE cluster via Helm and applies the root App of Apps manifest. This is the **one-time bridge** between Terraform (cloud infrastructure) and ArgoCD (Kubernetes lifecycle).

## The Separation of Concerns

```
Terraform ─── GCP Cloud Resources (VPC, GKE, IAM, Artifact Registry)
ArgoCD    ─── Everything Inside Kubernetes (apps, operators, config)
```

After this module runs, Terraform never manages Kubernetes resources again. All K8s changes go through Git → ArgoCD.

## Bootstrap Sequence

```
1. Terraform Phase 2  →  Networking (VPC, NAT, firewall, service accounts)
2. Terraform Phase 3  →  GKE cluster (private, regional, 3 node pools)
3. Terraform Phase 4  →  THIS MODULE: ArgoCD installed via Helm
                      →  Root Application applied
                      →  Workload Identity bindings for ArgoCD + ESO
4. ArgoCD             →  Discovers gitops/bootstrap/ → syncs all child apps
5. ArgoCD             →  gitops/platform/ → ESO, metrics-server
6. ArgoCD             →  gitops/observability/ → Prometheus, Grafana (Phase 8)
7. ArgoCD             →  gitops/applications/ → OTel Demo (Phase 5)
```

## Files

| File | Purpose |
|---|---|
| `main.tf` | `helm_release.argocd` + `kubernetes_manifest.root_application` + WI IAM bindings |
| `providers.tf` | Helm + Kubernetes providers authenticated via gcloud exec (ADC) |
| `variables.tf` | GKE cluster inputs, SA emails, chart version, Git repo URL |
| `outputs.tf` | Access commands for ArgoCD UI and admin password |
| `values.yaml` | ArgoCD Helm values (RBAC, Workload Identity, node scheduling, notifications) |
| `root-application.yaml` | App of Apps entry point template |

## Usage

```hcl
module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  project_id                = var.project_id
  cluster_name              = module.gke.cluster_name
  cluster_endpoint          = module.gke.cluster_endpoint
  cluster_ca_certificate    = module.gke.cluster_ca_certificate
  cluster_region            = module.gke.cluster_location
  argocd_sa_email           = module.service_accounts.argocd_sa_email
  external_secrets_sa_email = module.service_accounts.external_secrets_sa_email
  git_repo_url              = "https://github.com/YOUR_USERNAME/project-2.git"

  depends_on = [module.gke]
}
```

## Accessing the ArgoCD UI

```bash
# Get kubeconfig first
gcloud container clusters get-credentials otel-dev-gke --region=asia-south1

# Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Open https://localhost:8080 → login with admin / <password above>
```

## Important: Before Applying

1. **Update `git_repo_url`** in `terraform.tfvars` with your actual GitHub repo URL
2. **Make the repo public**, OR configure ArgoCD with a deploy key for private repos
3. Ensure the `gitops/bootstrap/` directory contains the namespace, projects, and appset manifests (created in Step 2)

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | required | GCP project ID |
| `cluster_name` | `string` | required | GKE cluster name |
| `cluster_endpoint` | `string` | required | GKE API server IP |
| `cluster_ca_certificate` | `string` | required | Base64 CA cert |
| `cluster_region` | `string` | `asia-south1` | Cluster region |
| `argocd_sa_email` | `string` | required | ArgoCD GCP SA email |
| `external_secrets_sa_email` | `string` | required | ESO GCP SA email |
| `argocd_chart_version` | `string` | `7.7.10` | Pinned chart version |
| `git_repo_url` | `string` | required | GitHub monorepo URL |

## Outputs

| Name | Description |
|---|---|
| `argocd_namespace` | Namespace where ArgoCD is installed |
| `argocd_access_command` | Port-forward command |
| `argocd_password_command` | Command to get initial admin password |
