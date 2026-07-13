# Output → Input Flow Across All Modules

> This document traces every output from every module to where it is consumed.  
> Use this as a cross-reference when debugging "unknown value" or "dependency not found" errors.

---

## Complete Output Flow Graph

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         environments/dev/main.tf                           │
│                                                                             │
│  module.project ──────────────────────────────────────────────────────────┐│
│    ↳ depends_on anchor for: networking, service_accounts,                  ││
│      artifact_registry, github_wif                                         ││
│                                                                             ││
│  module.networking                                                          ││
│    vpc_name ──────────────────────────────────────────────────────────────►│ module.cloud_router
│    vpc_name ──────────────────────────────────────────────────────────────►│ module.firewall
│    vpc_name ──────────────────────────────────────────────────────────────►│ module.gke
│    gke_subnet_name ───────────────────────────────────────────────────────►│ module.gke
│    gke_pods_range_name ───────────────────────────────────────────────────►│ module.gke
│    gke_services_range_name ───────────────────────────────────────────────►│ module.gke
│                                                                             ││
│  module.cloud_router                                                        ││
│    router_name ───────────────────────────────────────────────────────────►│ module.nat
│                                                                             ││
│  module.nat                                                                 ││
│    nat_name ──────────────────────────────────────────────────────────────►│ module.gke (as depends_on_nat)
│                                                                             ││
│  module.service_accounts                                                    ││
│    gke_node_sa_email ─────────────────────────────────────────────────────►│ module.gke
│    gke_node_sa_email ─────────────────────────────────────────────────────►│ module.artifact_registry
│    argocd_sa_email ───────────────────────────────────────────────────────►│ module.gke
│    argocd_sa_email ───────────────────────────────────────────────────────►│ module.argocd_bootstrap
│    external_secrets_sa_email ─────────────────────────────────────────────►│ module.gke
│    external_secrets_sa_email ─────────────────────────────────────────────►│ module.argocd_bootstrap
│    github_actions_sa_email ───────────────────────────────────────────────►│ module.artifact_registry
│    github_actions_sa_email ───────────────────────────────────────────────►│ module.github_wif
│                                                                             ││
│  module.gke                                                                 ││
│    cluster_name ──────────────────────────────────────────────────────────►│ module.argocd_bootstrap
│    cluster_endpoint ──────────────────────────────────────────────────────►│ module.argocd_bootstrap
│    cluster_endpoint ──────────────────────────────────────────────────────►│ versions.tf (helm provider)
│    cluster_ca_certificate ────────────────────────────────────────────────►│ module.argocd_bootstrap
│    cluster_ca_certificate ────────────────────────────────────────────────►│ versions.tf (helm provider)
│    cluster_location ──────────────────────────────────────────────────────►│ module.argocd_bootstrap (as cluster_region)
│                                                                             ││
│  module.argocd_bootstrap                                                    ││
│    argocd_access_command ─────────────────────────────────────────────────►│ outputs.tf
│    argocd_password_command ───────────────────────────────────────────────►│ outputs.tf
│                                                                             ││
│  module.artifact_registry                                                   ││
│    registry_url ──────────────────────────────────────────────────────────►│ outputs.tf
│    docker_auth_command ───────────────────────────────────────────────────►│ outputs.tf
│                                                                             ││
│  module.github_wif                                                          ││
│    workload_identity_provider ────────────────────────────────────────────►│ outputs.tf → GCP_WIF_PROVIDER
│    github_actions_sa_email ───────────────────────────────────────────────►│ outputs.tf → GCP_SA_EMAIL
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Output → Input Table (Detailed)

### `module.networking` outputs

| Output Name | Type | Passed to Variable | In Module |
|------------|------|-------------------|-----------|
| `vpc_name` | string | `vpc_name` | `module.cloud_router` |
| `vpc_name` | string | `vpc_name` | `module.firewall` |
| `vpc_name` | string | `vpc_name` | `module.gke` |
| `vpc_self_link` | string | (outputs.tf only) | — |
| `gke_subnet_name` | string | `gke_subnet_name` | `module.gke` |
| `gke_pods_range_name` | string | `gke_pods_range_name` | `module.gke` |
| `gke_services_range_name` | string | `gke_services_range_name` | `module.gke` |

### `module.cloud_router` outputs

| Output Name | Type | Passed to Variable | In Module |
|------------|------|-------------------|-----------|
| `router_name` | string | `router_name` | `module.nat` |

### `module.nat` outputs

| Output Name | Type | Passed to Variable | In Module |
|------------|------|-------------------|-----------|
| `nat_name` | string | `depends_on_nat` | `module.gke` (creates implicit dep) |
| `nat_name` | string | (outputs.tf) | — |

### `module.service_accounts` outputs

| Output Name | SA | Passed to Variable | In Module |
|------------|-----|-------------------|-----------|
| `gke_node_sa_email` | `sa-gke-nodes` | `gke_node_sa_email` | `module.gke` (node pool `service_account`) |
| `gke_node_sa_email` | `sa-gke-nodes` | `gke_node_sa_email` | `module.artifact_registry` (reader IAM) |
| `argocd_sa_email` | `sa-argocd` | `argocd_sa_email` | `module.gke` (passed to WI binding) |
| `argocd_sa_email` | `sa-argocd` | `argocd_sa_email` | `module.argocd_bootstrap` (WI binding + values.yaml annotation) |
| `external_secrets_sa_email` | `sa-external-secrets` | `external_secrets_sa_email` | `module.gke` |
| `external_secrets_sa_email` | `sa-external-secrets` | `external_secrets_sa_email` | `module.argocd_bootstrap` (WI binding) |
| `github_actions_sa_email` | `sa-github-actions` | `github_actions_sa_email` | `module.artifact_registry` (writer IAM) |
| `github_actions_sa_email` | `sa-github-actions` | `github_actions_sa_email` | `module.github_wif` (WIF IAM binding) |

### `module.gke` outputs

| Output Name | Sensitive | Passed to Variable | In Module |
|------------|-----------|-------------------|-----------|
| `cluster_name` | no | `cluster_name` | `module.argocd_bootstrap` |
| `cluster_endpoint` | **yes** | `cluster_endpoint` | `module.argocd_bootstrap` |
| `cluster_endpoint` | **yes** | `host` | `versions.tf` helm provider |
| `cluster_ca_certificate` | **yes** | `cluster_ca_certificate` | `module.argocd_bootstrap` |
| `cluster_ca_certificate` | **yes** | `cluster_ca_certificate` | `versions.tf` helm provider (`base64decode()`) |
| `cluster_location` | no | `cluster_region` | `module.argocd_bootstrap` |
| `workload_identity_pool` | no | (outputs.tf) | — |
| `get_credentials_command` | no | (outputs.tf) | — |

### `module.argocd_bootstrap` outputs

| Output Name | Value | Consumed By |
|------------|-------|-------------|
| `argocd_namespace` | `"argocd"` | outputs.tf verification |
| `argocd_chart_version` | `"7.7.10"` | outputs.tf verification |
| `argocd_access_command` | port-forward cmd | outputs.tf → printed post-apply |
| `argocd_password_command` | kubectl secret cmd | outputs.tf → printed post-apply |

### `module.artifact_registry` outputs

| Output Name | Value | Consumed By |
|------------|-------|-------------|
| `registry_url` | `asia-south1-docker.pkg.dev/{project}/platform` | outputs.tf → Docker push prefix |
| `docker_auth_command` | `gcloud auth configure-docker ...` | outputs.tf → run once before push |

### `module.github_wif` outputs

| Output Name | Value | Consumed By |
|------------|-------|-------------|
| `workload_identity_provider` | full WIF provider resource name | outputs.tf → set as `GCP_WIF_PROVIDER` in GitHub |
| `workload_identity_pool_name` | pool resource name | informational |
| `github_actions_sa_email` | `sa-github-actions` email | outputs.tf → set as `GCP_SA_EMAIL` in GitHub |

---

## Why Certain Values Are `sensitive = true`

`cluster_endpoint` and `cluster_ca_certificate` are marked sensitive because:
- Together with an access token, they provide **full cluster access**
- Terraform won't print them in plan/apply output
- They still flow through module outputs and provider config, but won't appear in logs

---

## Dependency Graph (Text Format)

```
project
  ↓
  ├── networking
  │     ↓
  │     ├── cloud_router
  │     │     ↓
  │     │     └── nat
  │     │           ↓ (depends_on_nat)
  │     └── firewall
  │
  ├── service_accounts
  │
  └── [networking + service_accounts + nat] → gke
                                                ↓
                                          argocd_bootstrap
                                          (installs ArgoCD + root app)
                                          (creates WI IAM bindings)
                                                ↓
                                          [Terraform ends — ArgoCD takes over]
  ↓
  ├── artifact_registry
  └── github_wif
```
