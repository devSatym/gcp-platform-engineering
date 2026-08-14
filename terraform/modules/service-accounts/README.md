# Module: service-accounts

Creates dedicated GCP service accounts for each platform component with least-privilege IAM bindings.

## Design Principles

- **No default SA**: We never use the default Compute Engine service account, which has excessive permissions.
- **Least privilege**: Each SA gets only the minimum roles needed for its function.
- **No JSON keys**: All SAs are designed for keyless authentication:
  - GKE nodes: automatically authenticated via VM metadata
  - ArgoCD, ESO: Workload Identity (K8s SA → GCP SA, configured in Phase 4)
  - GitHub Actions: Workload Identity Federation (OIDC token → GCP SA, Phase 6)
- **`sa-terraform` excluded**: Created in `bootstrap.sh` to avoid the chicken-and-egg problem of Terraform needing an SA before it can manage one.

## Service Accounts

| SA Name | Component | Key Roles |
|---|---|---|
| `sa-gke-nodes` | GKE node VMs | `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `artifactregistry.reader`, `stackdriver.resourceMetadata.writer` |
| `sa-argocd` | ArgoCD (Phase 4) | `secretmanager.secretAccessor` |
| `sa-external-secrets` | External Secrets Operator (Phase 4) | `secretmanager.secretAccessor`, `secretmanager.viewer` |
| `sa-github-actions` | GitHub Actions CI | `artifactregistry.writer`, `container.viewer` |

## Usage

```hcl
module "service_accounts" {
  source     = "../../modules/service-accounts"
  project_id = var.project_id
  labels     = local.labels
  depends_on = [module.project]
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | required | GCP project ID |
| `labels` | `map(string)` | `{}` | Resource labels |

## Outputs

| Name | Description |
|---|---|
| `gke_node_sa_email` | GKE node SA email — used in Phase 3 cluster config |
| `argocd_sa_email` | ArgoCD SA email — used in Phase 4 Workload Identity |
| `external_secrets_sa_email` | ESO SA email — used in Phase 4 Workload Identity |
| `github_actions_sa_email` | GitHub Actions SA — used in Phase 6 WIF config |
