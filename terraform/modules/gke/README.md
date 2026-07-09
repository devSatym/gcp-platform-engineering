# Module: gke

Creates a production-grade, private, regional GKE cluster with multiple node pools, hardened security, Workload Identity, Dataplane V2, and managed operations.

## Architecture

```
                      GCP Project
                          │
                    Private VPC (Phase 2)
                          │
              Private GKE Cluster (asia-south1)
                          │
       ┌──────────────────┼──────────────────┐
       │                  │                  │
  system-pool        general-pool       spot-pool
  (e2-medium)       (e2-standard-4)   (e2-standard-2)
  1–2 nodes/zone    1–5 nodes/zone    0–3 nodes/zone (Spot)
  CriticalAddons    Business services  Load gen, chaos
  taint             no taint          spot taint
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
                  Workload Identity
                          │
            ┌─────────────┼──────────────┐
            │             │              │
       Secret Manager  Artifact      Cloud Logging
                       Registry      + Monitoring
```

## Security Features

| Feature | Status | Notes |
|---|---|---|
| Private nodes (no public IPs) | ✅ Enabled | `enable_private_nodes = true` |
| Workload Identity | ✅ Enabled | `{project}.svc.id.goog` |
| Dataplane V2 (eBPF) | ✅ Enabled | `ADVANCED_DATAPATH_V2` |
| Network Policies | ✅ Enabled | Enforced by Dataplane V2 |
| Shielded Nodes | ✅ Enabled | Secure Boot + Integrity Monitoring |
| Binary Authorization | 🔵 Disabled | Enabled + enforced in Phase 7 |
| GKE Metadata Server | ✅ Enabled | `GKE_METADATA` mode on all pools |
| Legacy metadata API | 🚫 Blocked | `disable-legacy-endpoints = true` |
| Release channel | ✅ REGULAR | Managed patch + minor upgrades |
| Maintenance windows | ✅ Configured | Mon–Fri 02:00–06:00 IST |

## Node Pools

| Pool | Machine | Min–Max (per zone) | Spot | Taint | Label |
|---|---|---|---|---|---|
| `system-pool` | `e2-medium` (2vCPU/4GB) | 1–2 | No | `workload=system:NoSchedule` | `workload=system` |
| `general-pool` | `e2-standard-4` (4vCPU/16GB) | 1–5 | No | None | `workload=general` |
| `spot-pool` | `e2-standard-2` (2vCPU/8GB) | 0–3 | Yes ✅ | `workload=spot:NoSchedule` | `workload=spot` |

### Scheduling Workloads

To run a pod on a specific pool:

**System pool** (requires toleration):
```yaml
tolerations:
- key: "workload"
  operator: "Equal"
  value: "system"
  effect: "NoSchedule"
nodeSelector:
  workload: system
```

**General pool** (no toleration needed):
```yaml
nodeSelector:
  workload: general
```

**Spot pool** (requires toleration):
```yaml
tolerations:
- key: "workload"
  operator: "Equal"
  value: "spot"
  effect: "NoSchedule"
nodeSelector:
  workload: spot
```

## Usage

```hcl
module "gke" {
  source     = "../../modules/gke"
  project_id = var.project_id
  region     = var.region
  labels     = local.labels

  cluster_name            = "otel-${var.environment}-gke"
  vpc_name                = module.networking.vpc_name
  gke_subnet_name         = module.networking.gke_subnet_name
  gke_pods_range_name     = module.networking.gke_pods_range_name
  gke_services_range_name = module.networking.gke_services_range_name
  gke_node_sa_email       = module.service_accounts.gke_node_sa_email

  system_pool_min_count     = 1
  system_pool_max_count     = 2
  general_pool_min_count    = 1
  general_pool_max_count    = 3
  spot_pool_min_count       = 0
  spot_pool_max_count       = 2

  enable_private_endpoint = false           # true for prod
  master_authorized_cidr  = "0.0.0.0/0"   # restrict for prod

  depends_on = [module.networking, module.service_accounts, module.nat]
}
```

## Getting Cluster Credentials

```bash
gcloud container clusters get-credentials otel-dev-gke \
  --region=asia-south1 \
  --project=YOUR_PROJECT_ID

kubectl cluster-info
kubectl get nodes -L workload   # see pool labels
```

Or use the Terraform output:
```bash
terraform output get_credentials_command | bash
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | required | GCP project ID |
| `region` | `string` | `asia-south1` | GCP region |
| `cluster_name` | `string` | required | Cluster name (`otel-{env}-gke`) |
| `vpc_name` | `string` | required | VPC from networking module |
| `gke_subnet_name` | `string` | required | GKE subnet from networking module |
| `gke_pods_range_name` | `string` | `gke-pods` | Pod secondary range name |
| `gke_services_range_name` | `string` | `gke-services` | Service secondary range name |
| `gke_node_sa_email` | `string` | required | Node SA from service-accounts module |
| `master_ipv4_cidr_block` | `string` | `172.16.0.0/28` | Control plane CIDR |
| `enable_private_endpoint` | `bool` | `false` | Restrict API server to VPC |
| `master_authorized_cidr` | `string` | `0.0.0.0/0` | Allowed API server CIDR |
| `system_pool_machine_type` | `string` | `e2-medium` | System pool VM size |
| `general_pool_machine_type` | `string` | `e2-standard-4` | General pool VM size |
| `spot_pool_machine_type` | `string` | `e2-standard-2` | Spot pool VM size |
| `labels` | `map(string)` | `{}` | Resource labels |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | Cluster name |
| `cluster_endpoint` | API server IP (sensitive) |
| `cluster_ca_certificate` | CA cert (sensitive) |
| `cluster_location` | Region |
| `workload_identity_pool` | `{project}.svc.id.goog` |
| `system_pool_name` | System pool name |
| `general_pool_name` | General pool name |
| `spot_pool_name` | Spot pool name |
| `get_credentials_command` | gcloud command for kubeconfig |

## Comparison: Upstream Demo vs Our Platform

| Feature | Upstream OTel Demo | This Platform |
|---|---|---|
| Cluster provisioning | Assumes cluster exists | Terraform-managed |
| Node topology | Single pool | 3 pools with workload isolation |
| Node security | Default (public IPs) | Private nodes, Shielded |
| Authentication | Default SA / RBAC | Workload Identity (keyless) |
| Networking | Default kube-proxy | Dataplane V2 (eBPF) |
| Operations | Manual | Release channel + maintenance windows |
| Autoscaling | None | Cluster Autoscaler + VPA |
| Binary Auth | None | Prepared (Phase 7) |
