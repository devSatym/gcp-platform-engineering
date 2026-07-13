# Supporting Modules: `project`, `cloud-router`, `nat`, `firewall`

> These modules are simpler but critical dependencies in the apply chain.

---

## Module: `project`

> **Path:** `terraform/modules/project/`  
> **Must run FIRST** — all other modules depend on APIs being enabled.

### `main.tf` — Resource: `google_project_service "apis"`

Enables all GCP APIs via `for_each` over a `toset`:

```hcl
resource "google_project_service" "apis" {
  for_each = local.apis
  project  = var.project_id
  service  = each.value
  disable_on_destroy = false   # Never disable on destroy — takes time to re-enable
}
```

**`disable_on_destroy = false`** — critical. If set to `true`, `terraform destroy` disables APIs and the next `apply` fails while APIs are re-enabling.

### APIs Enabled by Phase

| Phase | APIs |
|-------|------|
| Phase 2 (Foundation) | `compute`, `cloudresourcemanager`, `iam`, `storage`, `iamcredentials`, `sts` |
| Phase 3 (GKE) | `container` |
| Phase 5 (Applications) | `artifactregistry`, `dns` |
| Phase 6 (Secrets) | `secretmanager` |
| Phase 7 (Security) | `binaryauthorization`, `containeranalysis`, `containerscanning` |
| Phase 8 (Observability) | `logging`, `monitoring`, `cloudtrace` |
| Phase 14 (Backup) | `gkebackup` |

**All APIs are enabled in one `apply` even if the associated phase hasn't run yet.** This avoids surprises when later phases create resources.

### Outputs

| Output | Value |
|--------|-------|
| `project_id` | `var.project_id` (pass-through) |
| `project_number` | `data.google_project.project.number` |

### Consumed By

`depends_on = [module.project]` in: `module.networking`, `module.service_accounts`, `module.artifact_registry`, `module.github_wif`

---

## Module: `cloud-router`

> **Path:** `terraform/modules/cloud-router/`  
> **Depends on:** `module.networking`  
> **Required by:** `module.nat`

### Purpose

Cloud Router is a prerequisite for Cloud NAT. It advertises routes and manages BGP sessions.

### Key Variable Flow

| Input | Source |
|-------|--------|
| `vpc_name` | `module.networking.vpc_name` |
| `project_id` | `var.project_id` |
| `region` | `var.region` |

### Output

| Output | Consumed By |
|--------|-------------|
| `router_name` | `module.nat.router_name` |

---

## Module: `nat`

> **Path:** `terraform/modules/nat/`  
> **Depends on:** `module.cloud_router`  
> **Required by:** `module.gke` (indirectly via `depends_on_nat`)

### Purpose

Cloud NAT gives private GKE nodes outbound internet access without public IPs. Required for nodes to pull container images from `docker.io`, `ghcr.io`, etc.

### Key Variable Flow

| Input | Source |
|-------|--------|
| `router_name` | `module.cloud_router.router_name` |
| `project_id` | `var.project_id` |
| `region` | `var.region` |

### Output

| Output | Consumed By |
|--------|-------------|
| `nat_name` | `module.gke` via `depends_on_nat = module.nat.nat_name` |

**Why `depends_on_nat` as a variable?**  
Terraform doesn't support `depends_on` that references another module in a child module's variable — only at the calling level. Passing the NAT name as a variable creates an **implicit dependency** without needing `depends_on` in the module's internal code.

---

## Module: `firewall`

> **Path:** `terraform/modules/firewall/`  
> **Depends on:** `module.networking`

### Purpose

Applies least-privilege ingress rules to the VPC.

### Key Variable Flow

| Input | Source |
|-------|--------|
| `vpc_name` | `module.networking.vpc_name` |
| `project_id` | `var.project_id` |
| `internal_cidr` | `"10.0.0.0/16"` (hardcoded in main.tf) |

### Typical Firewall Rules Created

| Rule | Direction | Source | Ports | Purpose |
|------|-----------|--------|-------|---------|
| allow-internal | INGRESS | `10.0.0.0/16` | all | Pod-to-pod, node-to-node |
| allow-health-checks | INGRESS | GCP health check ranges | HTTP | Load balancer health checks |
| allow-gke-master | INGRESS | control plane CIDR | 443, 10250 | GKE control plane → nodes |
| deny-all | INGRESS | 0.0.0.0/0 | all | Default deny (if explicit deny rule is used) |

### Output

| Output | Consumed By |
|--------|-------------|
| `firewall_rule_names` | `environments/dev/outputs.tf` → printed for verification |
