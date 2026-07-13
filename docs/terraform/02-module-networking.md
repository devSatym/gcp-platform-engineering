# Module: `networking`

> **Path:** `terraform/modules/networking/`  
> **Called from:** `environments/dev/main.tf` → `module "networking"`  
> **Phase:** 2 (Foundation)

---

## Files

| File | Purpose |
|------|---------|
| `main.tf` | VPC + 3 subnets (gke, management, proxy) |
| `variables.tf` | CIDR inputs, region, project, labels, vpc_name |
| `outputs.tf` | vpc_name, subnet names, secondary range names |

---

## `main.tf` — Resources

### `google_compute_network "vpc"`

```hcl
resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.vpc_name          # default: "platform-vpc"
  auto_create_subnetworks = false                 # Custom-mode: explicit subnets only
  routing_mode            = "REGIONAL"            # No multi-region routing
  mtu                     = 1460
  description             = "Platform Engineering VPC — managed by Terraform"
}
```

**Design decision:** `auto_create_subnetworks = false` reduces attack surface — no subnets created in unintended regions.

---

### `google_compute_subnetwork "gke"` — Primary GKE subnet

```hcl
resource "google_compute_subnetwork" "gke" {
  name    = "gke-subnet"
  region  = var.region
  network = google_compute_network.vpc.id
  ip_cidr_range            = var.gke_subnet_cidr      # 10.0.0.0/20 (node IPs)
  private_ip_google_access = true                     # Nodes reach GCP APIs without public IPs

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = var.gke_pods_cidr               # 10.10.0.0/16 (65,534 pod IPs)
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = var.gke_services_cidr            # 10.20.0.0/20 (4,094 service IPs)
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}
```

**Secondary ranges are mandatory for VPC-native GKE (alias IPs).** Must be declared before the GKE cluster.  
**VPC Flow Logs** are enabled at 50% sampling for network debugging.

---

### `google_compute_subnetwork "management"` — Admin subnet

```hcl
resource "google_compute_subnetwork" "management" {
  name          = "management-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range            = var.management_subnet_cidr  # 10.0.16.0/24
  private_ip_google_access = true
}
```

**Used for:** Bastion hosts, admin VMs, Cloud Shell connectivity.

---

### `google_compute_subnetwork "proxy"` — Proxy subnet for Gateway API

```hcl
resource "google_compute_subnetwork" "proxy" {
  name          = "proxy-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.proxy_subnet_cidr              # 10.0.17.0/24
  purpose       = "REGIONAL_MANAGED_PROXY"            # Reserved for Google-managed Envoy
  role          = "ACTIVE"
}
```

**Required by:** GKE Gateway API (Phase 9) and internal Application Load Balancers.  
**`purpose = "REGIONAL_MANAGED_PROXY"`** makes this subnet reserved — no user workloads can be placed here.

---

## `outputs.tf` — What Gets Exported and Where It Goes

| Output | Value | Consumed By |
|--------|-------|-------------|
| `vpc_name` | `google_compute_network.vpc.name` | `module.cloud_router`, `module.firewall`, `module.gke` |
| `vpc_id` | `google_compute_network.vpc.id` | Informational |
| `vpc_self_link` | `google_compute_network.vpc.self_link` | `module.firewall`, `outputs.tf` |
| `gke_subnet_name` | `"gke-subnet"` | `module.gke.gke_subnet_name` |
| `gke_subnet_self_link` | `google_compute_subnetwork.gke.self_link` | `outputs.tf` |
| `gke_subnet_cidr` | `google_compute_subnetwork.gke.ip_cidr_range` | Informational |
| `gke_pods_range_name` | `"gke-pods"` | `module.gke.gke_pods_range_name` → `ip_allocation_policy.cluster_secondary_range_name` |
| `gke_services_range_name` | `"gke-services"` | `module.gke.gke_services_range_name` → `ip_allocation_policy.services_secondary_range_name` |
| `management_subnet_name` | `"management-subnet"` | Informational |
| `proxy_subnet_name` | `"proxy-subnet"` | Informational |

---

## IP Plan Summary

```
VPC:           10.0.0.0/16   (entire platform)
  ├── gke-subnet       10.0.0.0/20    (GKE node VMs)
  │     ├── gke-pods      10.10.0.0/16  (secondary range — pod IPs)
  │     └── gke-services  10.20.0.0/20  (secondary range — ClusterIP IPs)
  ├── management-subnet  10.0.16.0/24   (bastion, admin)
  └── proxy-subnet       10.0.17.0/24   (Google-managed Envoy for Gateway API)
```
