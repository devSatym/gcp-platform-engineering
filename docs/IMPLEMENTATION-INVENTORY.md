# Platform Engineering GCP — Complete Implementation Inventory (Phases 1-6)

## Project Overview

A production-grade **Platform Engineering** project on Google Cloud, deploying the OpenTelemetry Demo (Astronomy Shop) as a showcase workload. The platform is designed around GitOps principles: Terraform owns GCP infrastructure, ArgoCD owns everything inside Kubernetes, and GitHub Actions automates the software supply chain.

---

## Phase 1 — Project Bootstrapping

### What was built

| File | Purpose |
|---|---|
| `bootstrap/bootstrap.sh` | One-time script that enables GCP APIs, creates the Terraform state bucket (`{project}-tf-state`), creates `sa-terraform` SA, grants it IAM roles, and outputs next steps. |

### Resources created by bootstrap.sh
- GCS bucket: `{project_id}-tf-state` (versioned, lifecycle, uniform access)
- SA: `sa-terraform` with roles: `editor`, `projectIamAdmin`, `storageAdmin`, `serviceAccountAdmin`, `serviceAccountKeyAdmin`, `serviceUsageAdmin`
- APIs: `cloudresourcemanager`, `iam`, `storage`, `compute`

---

## Phase 2 — Networking, IAM & Foundation Infrastructure

### Terraform Modules (6 modules)

#### 1. `terraform/modules/project/` (4 files)
Enables all required GCP APIs.

| File | Content |
|---|---|
| `main.tf` | `google_project_service` for 12+ APIs (container, compute, secretmanager, iam, artifactregistry, etc.) |
| `variables.tf` | `project_id`, `labels` |
| `outputs.tf` | `project_id` |
| `README.md` | Module documentation |

#### 2. `terraform/modules/networking/` (4 files)
VPC, subnets, and secondary IP ranges for GKE pods/services.

| File | Content |
|---|---|
| `main.tf` | `google_compute_network` (VPC), `google_compute_subnetwork` (gke-subnet, management-subnet, proxy-only-subnet), secondary ranges for pods and services |
| `variables.tf` | CIDR configurations, project_id, region |
| `outputs.tf` | `vpc_name`, `vpc_self_link`, `gke_subnet_name`, `gke_pods_range_name`, `gke_services_range_name` |
| `README.md` | IP plan documentation |

**IP Plan:**
| Range | CIDR | Capacity |
|---|---|---|
| GKE nodes | `10.0.0.0/20` | 4094 IPs |
| Management | `10.0.16.0/24` | 254 IPs |
| Proxy-only | `10.0.17.0/24` | 254 IPs |
| Pods (secondary) | `10.10.0.0/16` | 65K IPs |
| Services (secondary) | `10.20.0.0/20` | 4094 IPs |

#### 3. `terraform/modules/cloud-router/` (4 files)
Cloud Router — prerequisite for Cloud NAT.

#### 4. `terraform/modules/nat/` (4 files)
Cloud NAT — provides outbound internet for private GKE nodes.

#### 5. `terraform/modules/firewall/` (4 files)
Firewall rules: internal communication, IAP SSH, health checks, GKE webhook admission.

#### 6. `terraform/modules/service-accounts/` (4 files)
5 dedicated GCP service accounts with least-privilege IAM.

| SA Name | Roles | Used By |
|---|---|---|
| `sa-gke-nodes` | logging.logWriter, monitoring.metricWriter, monitoring.viewer, stackdriver.resourceMetadata.writer, artifactregistry.reader | GKE node pools |
| `sa-argocd` | container.clusterAdmin, secretmanager.secretAccessor | ArgoCD via Workload Identity |
| `sa-external-secrets` | secretmanager.secretAccessor | ESO via Workload Identity |
| `sa-github-actions` | artifactregistry.writer, container.developer, iam.serviceAccountTokenCreator | GitHub Actions CI/CD (Phase 6) |
| `sa-terraform` | Created by bootstrap.sh | Terraform operations |

### Environment Configs (3 environments × 7 files each = 21 files)

Each environment (`dev/`, `stage/`, `prod/`) has:
| File | Content |
|---|---|
| `main.tf` | Module composition — calls all 10 modules |
| `variables.tf` | `project_id`, `region`, `environment` |
| `terraform.tfvars` | Actual values for `project_id`, `region`, `environment` |
| `locals.tf` | Common labels (environment, team, project, managed-by, owner) |
| `versions.tf` | Terraform ≥1.5, google ≥5.0, google-beta ≥5.0, provider config |
| `backend.tf` | GCS backend with environment-specific state prefix |
| `outputs.tf` | Re-exports from all modules |

---

## Phase 3 — GKE Private Regional Cluster

### `terraform/modules/gke/` (9 files)

| File | Content |
|---|---|
| `cluster.tf` | Private regional GKE cluster with Workload Identity, VPC-native networking, release channel REGULAR, Shielded Nodes, Binary Authorization (audit mode), master authorized networks |
| `nodepools.tf` | 3 node pools: system (e2-medium, taint workload=system), general (e2-standard-4, label workload=general), spot (e2-standard-2, preemptible, taint workload=spot, label workload=spot) |
| `autoscaling.tf` | Cluster autoscaler config, autoscaling profiles, resource limits |
| `logging.tf` | GKE logging config (system + workload components) |
| `monitoring.tf` | GKE monitoring config (system + API server + scheduler + controller metrics) |
| `workload_identity.tf` | 3 IAM bindings: ArgoCD server, ArgoCD repo-server, External Secrets → their respective GCP SAs |
| `variables.tf` | Cluster name, networking inputs, node pool sizing, WI SA emails |
| `outputs.tf` | `cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`, `cluster_location`, `workload_identity_pool`, `get_credentials_command` |
| `README.md` | Cluster architecture documentation |

---

## Phase 4 — GitOps Platform Bootstrap (ArgoCD)

### Terraform Module

#### `terraform/modules/argocd-bootstrap/` (7 files)

| File | Content |
|---|---|
| `main.tf` | Helm release (ArgoCD), `kubectl_manifest` for root Application, WI IAM bindings |
| `providers.tf` | Helm + Kubernetes providers via `gcloud exec` credential plugin |
| `variables.tf` | Cluster details, SA emails, chart version (default `7.7.7`), git repo URL |
| `outputs.tf` | ArgoCD namespace, port-forward command, admin password command |
| `values.yaml` | RBAC (admin/developer/readonly), WI annotations, system pool scheduling, resource tracking |
| `root-application.yaml` | App of Apps template — watches `gitops/bootstrap/` |
| `README.md` | Bootstrap sequence, access instructions, DR procedure |

### GitOps Manifests

#### `gitops/bootstrap/` (4 files)

| File | Content |
|---|---|
| `namespaces.yaml` | 9 namespaces: argocd, platform-system, observability, security, networking, applications, otel-demo-dev, otel-demo-stage, otel-demo-prod (sync wave -2) |
| `projects.yaml` | 5 ArgoCD Projects: platform, applications, observability, networking, security — each with scoped sourceRepos, destinations, and clusterResourceWhitelist |
| `platform-appset.yaml` | ApplicationSet generating `platform-dev/stage/prod` Applications pointing to `gitops/platform/` |
| `applications-appset.yaml` | ApplicationSet generating `otel-demo-dev/stage/prod` from upstream OTel Helm chart + our values overlays (Phase 5) |

#### `gitops/platform/` (4 files)

| File | Content |
|---|---|
| `external-secrets.yaml` | ArgoCD Application installing ESO via Helm (wave 0), WI SA annotation, system pool scheduling |
| `metrics-server.yaml` | ArgoCD Application installing metrics-server (wave 1), GKE kubelet-insecure-tls flag |
| `priority-classes.yaml` | 4 PriorityClasses: platform-critical(1000), business-critical(900), business-standard(500, globalDefault), non-critical(100) (wave 0) |
| `README.md` | Platform component documentation |

#### `gitops/environments/` (3 files)

| File | Content |
|---|---|
| `dev/values-common.yaml` | Dev overrides for platform components: 1 replica, low resources |
| `stage/values-common.yaml` | Stage overrides: 2 replicas, moderate resources |
| `prod/values-common.yaml` | Prod overrides: 3 replicas, high resources, Prometheus persistence |

#### `gitops/README.md`
Bootstrap sequence, App of Apps architecture, sync wave ordering, DR procedure.

---

## Phase 5 — OTel Demo Deployment & Productionization

### Terraform Module

#### `terraform/modules/artifact-registry/` (4 files)

| File | Content |
|---|---|
| `main.tf` | Docker registry (`platform-docker`), lifecycle cleanup (keep 10 tagged, delete untagged), GKE node reader IAM, GitHub Actions writer IAM |
| `variables.tf` | project_id, region, repository_id, gke_node_sa_email, github_actions_sa_email |
| `outputs.tf` | `registry_url`, `repository_id`, `docker_auth_command` |
| `README.md` | Image strategy, naming convention, lifecycle policy |

### GitOps Application Manifests

#### `gitops/applications/opentelemetry-demo/values/` (4 files)

| File | Content |
|---|---|
| `base.yaml` | All ~20 services with per-tier resources, PriorityClasses, nodeSelectors, tolerations (load-gen→spot), OTel Collector multi-backend config, Prometheus/Grafana persistence, OpenSearch disabled |
| `dev.yaml` | 1 replica each, load-gen enabled (10 users/1 spawn rate), debug logging, no Prometheus persistence |
| `stage.yaml` | 2 replicas for T1, PDBs minAvailable:1, load-gen 50 users, Prometheus 20Gi persistence |
| `prod.yaml` | 3 replicas for T1, PDBs minAvailable:2, zone anti-affinity, topology spread, load-gen disabled, Prometheus 50Gi/30d, payment hard zone constraint |

#### `gitops/applications/opentelemetry-demo/README.md`
Tier classification table, environment comparison matrix, port-forward commands, upgrade procedure.

---

## Phase 6 — Enterprise CI/CD & Software Supply Chain

### Terraform Module

#### `terraform/modules/github-wif/` (4 files)

| File | Content |
|---|---|
| `main.tf` | WIF pool (`github-pool`), OIDC provider (`github-provider`) with attribute mapping (subject, actor, repository, owner, workflow, ref), attribute condition restricting to specific repo, SA impersonation IAM binding |
| `variables.tf` | project_id, github_repo (owner/repo format), github_actions_sa_email |
| `outputs.tf` | `workload_identity_provider`, `workload_identity_pool_name`, `github_actions_sa_email` |
| `README.md` | WIF vs JSON key comparison, OIDC flow diagram, GitHub Actions usage |

### GitHub Actions Workflows

#### `.github/workflows/` (5 files)

| Workflow | Trigger | Pipeline |
|---|---|---|
| `ci.yaml` | PR to main | yamllint → Helm values syntax → Markdown lint → TF fmt+validate+tflint → Checkov → Gitleaks |
| `build.yaml` | Merge to main (paths: applications/**) | WIF auth → Buildx amd64+arm64 → layer cache → sha+build tags → AR push → GitOps update → commit |
| `security.yaml` | After build completes | Syft SBOM (CycloneDX+SPDX) → Trivy (SARIF→Security tab, CRITICAL=fail) → Cosign keyless sign → SLSA provenance |
| `release.yaml` | Tag push `v*` | Auto-changelog → GitHub Release → SBOM attached → version-tagged images |
| `terraform.yaml` | PR to terraform/** | fmt → validate (all envs+modules) → tflint → Checkov (SARIF) → plan (PR comment) |

### Composite Actions

#### `.github/actions/` (3 files)

| Action | Purpose |
|---|---|
| `gcp-auth/action.yaml` | Reusable WIF auth with optional Docker AR config |
| `docker-build/action.yaml` | Reusable Buildx multi-arch with cache management |
| `security-scan/action.yaml` | Reusable Syft + Trivy + Cosign pipeline |

### Scripts & Config

| File | Purpose |
|---|---|
| `.github/scripts/update-image-tag.sh` | Updates gitops/ image tags after build (sed-based, executable) |
| `renovate.json` | Automated dependency PRs: Helm charts, TF providers, GitHub Actions, Docker base images |

---

## Complete File Count

| Category | Count |
|---|---|
| Terraform modules | 9 directories, 40 `.tf` files |
| Terraform environments | 3 directories, 21 files |
| Bootstrap | 1 script |
| GitOps bootstrap | 4 YAML files |
| GitOps platform | 3 YAML files + 1 README |
| GitOps environments | 3 YAML files |
| GitOps applications | 4 YAML files + 1 README |
| GitHub Actions workflows | 5 YAML files |
| GitHub Actions composite | 3 YAML files |
| GitHub scripts | 1 shell script |
| Config files | 1 (renovate.json) |
| **Total managed files** | **~87 files** |

---

## Known Issues Found During Audit

### ❌ Issue 1: Stage/Prod outputs.tf missing 6 outputs
Dev has 27 outputs. Stage and Prod only have 21. Missing from stage/prod:
- `argocd_access_command`
- `argocd_password_command`
- `docker_auth_command`
- `registry_url`
- `github_actions_sa_email_wif`
- `wif_provider`

**Impact:** After `terraform apply` on stage/prod, these useful operational outputs won't be displayed.

### ⚠️ Issue 2: All placeholders still present
29 placeholder references across the codebase need updating before first apply:
- `YOUR_USERNAME` — 14 occurrences across Terraform and GitOps files
- `YOUR_PROJECT_ID` — 1 occurrence in ESO manifest
- `YOUR_GITHUB_USERNAME` — 4 occurrences in renovate.json
- `platform-engineering-demo` — default project ID in tfvars and bootstrap.sh

### ⚠️ Issue 3: Empty modules exist but aren't called
- `terraform/modules/dns/` — empty directory (no files)
- `terraform/modules/monitoring/` — empty directory (no files)

These are harmless placeholder directories for future phases but could confuse readers.

### ⚠️ Issue 4: Helm provider not declared in root versions.tf
The `argocd-bootstrap` module uses `helm` and `kubernetes` providers declared in its own `providers.tf`, but the root `versions.tf` doesn't declare `hashicorp/helm` or `hashicorp/kubernetes`. This works because the module has its own provider block, but best practice is to declare all required providers at the root level too.

### ⚠️ Issue 5: build.yaml references `applications/` path for Dockerfile
The build workflow matrix references `applications/otel-collector/Dockerfile` and `applications/otel-collector/` context, but this directory doesn't exist yet. The workflow will trigger on `applications/**` path changes but has no actual Dockerfiles to build.

**Impact:** Build workflow won't fail (it simply won't trigger), but the matrix is referencing non-existent paths. This is expected — custom Dockerfiles will be added when image mirroring begins.
