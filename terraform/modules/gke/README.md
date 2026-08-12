# GKE Cluster Module

Creates a reusable private or public regional GKE cluster with caller-defined
node pools, autoscaling, Workload Identity, Dataplane configuration, security
addons, and Google Cloud logging/monitoring integration.

This module is workload-neutral. It provisions cluster capacity and platform
capabilities; it does not know application chart names, namespaces, Services,
ports, replicas, dashboards, or pod placement rules. Workload placement and
resource behavior belong to the workload Helm values and Kubernetes policy
layer.

## Responsibilities

- GKE cluster and control-plane networking
- VPC-native pod and Service IP allocation
- caller-defined node pools, machine types, labels, taints, and autoscaling
- private nodes, authorized networks, release channel, and maintenance policy
- Workload Identity enablement
- Shielded nodes and Binary Authorization mode
- Gateway API, DNS, VPA, HPA, GCS Fuse, and network-policy addons
- GKE logging, monitoring, and Managed Service for Prometheus integration

Node-pool labels and taints are generic platform capacity classes. They are
not assignments to any particular workload. Workload GitOps configuration may
choose a compatible class when a platform policy permits it.

## Usage

```hcl
module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  cluster_name = var.cluster_name
  region       = var.region
  node_locations = var.node_locations
  labels       = var.labels

  network_name                  = module.networking.vpc_name
  subnetwork_name               = module.networking.gke_subnet_name
  pods_secondary_range_name     = module.networking.gke_pods_range_name
  services_secondary_range_name = module.networking.gke_services_range_name
  node_service_account          = module.service_accounts.gke_node_sa_email
  node_pools                    = var.node_pools
  autoscaling                   = var.autoscaling
  private_cluster               = var.private_cluster
  release_channel               = var.release_channel

  depends_on = [module.networking, module.service_accounts, module.nat]
}
```

## Security defaults

| Capability | Configuration |
|---|---|
| Private nodes | `private_cluster.enabled` |
| Private control-plane endpoint | `private_cluster.enable_private_endpoint` |
| Control-plane access | `private_cluster.master_authorized_cidrs` |
| Workload Identity | `enable_workload_identity` |
| Shielded nodes | `enable_shielded_nodes` |
| Dataplane | `datapath_provider` |
| Binary Authorization | `binary_authorization_mode` |
| Release updates | `release_channel` and maintenance settings |
| Node metadata | GKE metadata server when Workload Identity is enabled |

## Important boundary

The module exposes cluster and capacity primitives only. It must not acquire
inputs for workload chart identity, application service names, Deployment or
Rollout names, application ports, replica counts, application-specific
scheduling, or dashboards. Those concerns are owned by GitOps workload
configuration and validated by Kubernetes policy.

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | Cluster name |
| `cluster_endpoint` | API server endpoint (sensitive) |
| `cluster_ca_certificate` | Cluster CA certificate (sensitive) |
| `cluster_location` | Cluster region/location |
| `workload_identity_pool` | GKE Workload Identity pool |
| `node_pool_names` | Created node-pool names |
| `get_credentials_command` | gcloud command for kubeconfig |
