# `environments/dev/` — Root Module (Dev Environment)

> **Path:** `terraform/environments/dev/`  
> **Purpose:** The Terraform root module for the dev environment. Wires every module together in dependency order.

---

## Files in This Directory

| File | Role |
|------|------|
| `main.tf` | Calls all 10 modules in dependency order |
| `locals.tf` | Labels + platform sizing (single source of truth) |
| `variables.tf` | `project_id`, `region`, `environment` inputs |
| `outputs.tf` | Re-exports module outputs for verification |
| `backend.tf` | GCS remote state config |
| `versions.tf` | Provider pinning + provider configuration |
| `terraform.tfvars` | Actual values for variables |

---

## `backend.tf`

```hcl
terraform {
  backend "gcs" {
    bucket = "valiant-house-502004-k2-tfstate"
    prefix = "dev/foundation"   # State stored at gs://bucket/dev/foundation/default.tfstate
  }
}
```

**What it does:** Stores Terraform state in GCS instead of local disk.  
**Used by:** Every `terraform plan/apply/destroy` call reads/writes this bucket.  
**Dependency:** Bucket must be created first by `bootstrap/bootstrap.sh`.

---

## `versions.tf`

### `terraform {}` block

```hcl
required_version = ">= 1.5"
```

Pins providers:
| Provider | Version | Why |
|----------|---------|-----|
| `google` | `~> 5.0` | Core GCP resources |
| `google-beta` | `~> 5.0` | Beta features: `gateway_api_config`, Dataplane V2 |
| `helm` | `~> 2.12` | Installs ArgoCD in `argocd-bootstrap` module |
| `null` | `~> 3.0` | `null_resource` for kubectl + gcloud scripts |

### Provider blocks

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
```

Both use **Application Default Credentials (ADC)**. Locally: `gcloud auth application-default login`. In CI: Workload Identity Federation.

```hcl
data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}
```

**Helm provider reads:** `module.gke.cluster_endpoint` and `module.gke.cluster_ca_certificate`  
**Used by:** `module.argocd_bootstrap` → `helm_release.argocd`

---

## `locals.tf`

### `labels` block

```hcl
labels = {
  environment = var.environment   # "dev"
  team        = "platform"
  project     = "otel-demo"
  managed-by  = "terraform"
  owner       = "satyam"
}
```

**Passed to:** `module.project`, `module.networking`, `module.service_accounts`, `module.gke`, `module.artifact_registry`  

### `sizing` block (Platform Sizing — Single Source of Truth)

| Pool | Machine | vCPU/RAM | Min/Zone | Max/Zone | Hosts |
|------|---------|----------|----------|----------|-------|
| system | e2-medium | 2/4GB | 1 (→3 nodes) | 2 (→6 nodes) | ArgoCD, ESO, Prometheus, Falco |
| general | e2-standard-4 | 4/16GB | 1 (→3 nodes) | 3 (→9 nodes) | 20 OTel services, Grafana, Loki |
| spot | e2-standard-2 | 2/8GB | 0 | 2 (→6 nodes) | Load generator, chaos runners |

**NOTE:** `min_node_count` is **per zone**. Regional cluster = 3 zones. `min=1` → 3 nodes always running.

**Consumed in `main.tf` by:**
```hcl
module "gke" {
  system_pool_machine_type  = local.sizing.system_machine_type
  system_pool_min_count     = local.sizing.system_min_count
  ...
}
```

---

## `main.tf` — Module Call Order

### Module 1: `project`

```hcl
module "project" {
  source     = "../../modules/project"
  project_id = var.project_id
  labels     = local.labels
}
```

**What it does:** Enables all required GCP APIs.  
**Must run first** — all other resources depend on APIs being enabled.  
**`depends_on` chain:** `module.networking`, `module.service_accounts`, `module.artifact_registry`, `module.github_wif` all have `depends_on = [module.project]`.

---

### Module 2: `networking`

```hcl
module "networking" {
  source     = "../../modules/networking"
  project_id = var.project_id
  region     = var.region
  labels     = local.labels

  gke_subnet_cidr        = "10.0.0.0/20"
  management_subnet_cidr = "10.0.16.0/24"
  proxy_subnet_cidr      = "10.0.17.0/24"
  gke_pods_cidr          = "10.10.0.0/16"
  gke_services_cidr      = "10.20.0.0/20"

  depends_on = [module.project]
}
```

**Outputs consumed downstream:**
- `module.networking.vpc_name` → `module.cloud_router`, `module.firewall`, `module.gke`
- `module.networking.gke_subnet_name` → `module.gke`
- `module.networking.gke_pods_range_name` → `module.gke`
- `module.networking.gke_services_range_name` → `module.gke`

---

### Module 3: `cloud_router`

```hcl
module "cloud_router" {
  source     = "../../modules/cloud-router"
  project_id = var.project_id
  region     = var.region
  vpc_name   = module.networking.vpc_name    # ← from networking module

  depends_on = [module.networking]
}
```

**Output consumed by:** `module.nat.router_name = module.cloud_router.router_name`

---

### Module 4: `nat`

```hcl
module "nat" {
  source      = "../../modules/nat"
  project_id  = var.project_id
  region      = var.region
  router_name = module.cloud_router.router_name   # ← from cloud_router module

  depends_on = [module.cloud_router]
}
```

**Output consumed by:** `module.gke.depends_on_nat = module.nat.nat_name`  
**Why GKE depends on NAT:** Private GKE nodes need NAT to pull Docker images from internet.

---

### Module 5: `firewall`

```hcl
module "firewall" {
  source        = "../../modules/firewall"
  project_id    = var.project_id
  vpc_name      = module.networking.vpc_name    # ← from networking module
  internal_cidr = "10.0.0.0/16"

  depends_on = [module.networking]
}
```

---

### Module 6: `service_accounts`

```hcl
module "service_accounts" {
  source     = "../../modules/service-accounts"
  project_id = var.project_id
  labels     = local.labels

  depends_on = [module.project]
}
```

**Outputs consumed downstream:**
| Output | Used By |
|--------|---------|
| `gke_node_sa_email` | `module.gke`, `module.artifact_registry` |
| `argocd_sa_email` | `module.gke` (WI binding), `module.argocd_bootstrap` |
| `external_secrets_sa_email` | `module.gke` (WI binding), `module.argocd_bootstrap` |
| `github_actions_sa_email` | `module.artifact_registry`, `module.github_wif` |

---

### Module 7: `gke`

```hcl
module "gke" {
  source     = "../../modules/gke"
  project_id = var.project_id
  region     = var.region
  labels     = local.labels

  cluster_name            = "otel-${var.environment}-gke"  # "otel-dev-gke"
  vpc_name                = module.networking.vpc_name
  gke_subnet_name         = module.networking.gke_subnet_name
  gke_pods_range_name     = module.networking.gke_pods_range_name
  gke_services_range_name = module.networking.gke_services_range_name
  gke_node_sa_email       = module.service_accounts.gke_node_sa_email

  argocd_sa_email           = module.service_accounts.argocd_sa_email
  external_secrets_sa_email = module.service_accounts.external_secrets_sa_email

  # ── All sizes from local.sizing ──
  system_pool_machine_type  = local.sizing.system_machine_type
  system_pool_min_count     = local.sizing.system_min_count
  system_pool_max_count     = local.sizing.system_max_count
  general_pool_machine_type = local.sizing.general_machine_type
  general_pool_min_count    = local.sizing.general_min_count
  general_pool_max_count    = local.sizing.general_max_count
  spot_pool_machine_type    = local.sizing.spot_machine_type
  spot_pool_min_count       = local.sizing.spot_min_count
  spot_pool_max_count       = local.sizing.spot_max_count

  enable_private_endpoint = false     # Dev: public endpoint for local kubectl
  master_authorized_cidr  = "0.0.0.0/0"

  depends_on_nat = module.nat.nat_name
  depends_on = [module.networking, module.service_accounts, module.nat]
}
```

**Outputs consumed by `module.argocd_bootstrap`:**
- `cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`, `cluster_location`

**Outputs consumed by `versions.tf` Helm provider:**
- `cluster_endpoint`, `cluster_ca_certificate`

---

### Module 8: `argocd_bootstrap`

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

  git_repo_url = "https://github.com/devSatym/gcp-platform-engineering.git"

  depends_on = [module.gke]
}
```

**CRITICAL:** `depends_on = [module.gke]` is **required**.  
The WI identity pool (`{project}.svc.id.goog`) only exists **after** the GKE cluster with `workload_identity_config` is fully up. Running the WI IAM binding before cluster creation causes: `"Identity Pool does not exist" error 400`.

---

### Module 9: `artifact_registry`

```hcl
module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id              = var.project_id
  region                  = var.region
  gke_node_sa_email       = module.service_accounts.gke_node_sa_email
  github_actions_sa_email = module.service_accounts.github_actions_sa_email
  labels                  = local.labels

  depends_on = [module.project]
}
```

---

### Module 10: `github_wif`

```hcl
module "github_wif" {
  source = "../../modules/github-wif"

  project_id              = var.project_id
  github_repo             = "devSatym/gcp-platform-engineering"
  github_actions_sa_email = module.service_accounts.github_actions_sa_email

  depends_on = [module.project]
}
```

---

## `outputs.tf` — What Gets Exported

All outputs re-export module outputs. Key ones:

| Output | Source | Purpose |
|--------|--------|---------|
| `vpc_name` | `module.networking.vpc_name` | Verification |
| `cluster_endpoint` | `module.gke.cluster_endpoint` | kubectl access |
| `get_credentials_command` | `module.gke.get_credentials_command` | Copy-paste gcloud command |
| `argocd_access_command` | `module.argocd_bootstrap` | Port-forward command |
| `argocd_password_command` | `module.argocd_bootstrap` | Get initial admin password |
| `registry_url` | `module.artifact_registry` | Docker push prefix |
| `wif_provider` | `module.github_wif` | Set as GitHub Actions secret |
| `github_actions_sa_email_wif` | `module.github_wif` | Set as GitHub Actions secret |

---

## `variables.tf`

| Variable | Type | Description |
|----------|------|-------------|
| `project_id` | string | GCP project ID |
| `region` | string | Default: `asia-south1` |
| `environment` | string | Default: `dev` |
