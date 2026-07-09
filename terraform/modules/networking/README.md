# Module: networking

Creates the platform VPC with a private subnet architecture designed for a private GKE cluster.

## Purpose

This is the foundation module — all other infrastructure depends on the network. It creates a **custom-mode VPC** (no auto-created subnets) with three dedicated subnets and secondary IP ranges required for VPC-native GKE.

## IP Addressing Plan

| Resource | CIDR | Hosts | Purpose |
|---|---|---|---|
| VPC | `10.0.0.0/16` | 65,534 | Primary address space |
| GKE subnet (primary) | `10.0.0.0/20` | 4,094 | GKE node IPs |
| Management subnet | `10.0.16.0/24` | 254 | Bastion, admin VMs |
| Proxy subnet | `10.0.17.0/24` | 254 | Internal LB / Gateway API |
| GKE pods (secondary) | `10.10.0.0/16` | 65,534 | GKE pod alias IPs |
| GKE services (secondary) | `10.20.0.0/20` | 4,094 | GKE service ClusterIPs |

## Design Decisions

- **Custom-mode VPC**: Prevents accidental subnet creation in unwanted regions.
- **Private Google Access**: Enabled on GKE and management subnets — nodes reach Artifact Registry, Secret Manager, and Cloud Storage without public IPs.
- **Secondary ranges declared upfront**: GKE requires secondary ranges to exist before cluster creation. Declaring them now prevents networking refactors in Phase 3.
- **Proxy subnet**: Required for GCP-managed regional internal load balancers (Gateway API in Phase 9+). Must be declared before they're needed.
- **Flow logs**: Enabled on GKE subnet for security analysis and troubleshooting.

## Usage

```hcl
module "networking" {
  source     = "../../modules/networking"
  project_id = var.project_id
  region     = var.region
  labels     = local.labels
  depends_on = [module.project]
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | required | GCP project ID |
| `region` | `string` | `asia-south1` | GCP region |
| `vpc_name` | `string` | `platform-vpc` | VPC name |
| `gke_subnet_cidr` | `string` | `10.0.0.0/20` | GKE node subnet primary CIDR |
| `management_subnet_cidr` | `string` | `10.0.16.0/24` | Management subnet CIDR |
| `proxy_subnet_cidr` | `string` | `10.0.17.0/24` | Proxy subnet CIDR |
| `gke_pods_cidr` | `string` | `10.10.0.0/16` | GKE pods secondary range |
| `gke_services_cidr` | `string` | `10.20.0.0/20` | GKE services secondary range |
| `labels` | `map(string)` | `{}` | Resource labels |

## Outputs

| Name | Description |
|---|---|
| `vpc_name` | VPC name |
| `vpc_self_link` | VPC self-link for firewall rules |
| `gke_subnet_name` | GKE subnet name |
| `gke_subnet_self_link` | GKE subnet self-link for GKE cluster |
| `gke_pods_range_name` | Secondary range name for pods (`gke-pods`) |
| `gke_services_range_name` | Secondary range name for services (`gke-services`) |
| `management_subnet_name` | Management subnet name |
