# Module: nat

Creates a Cloud NAT gateway for outbound internet access from private GKE nodes.

## Purpose

Private GKE nodes have no public IP addresses. Cloud NAT provides outbound-only internet access for pulling container images, package updates, and external API calls — without exposing nodes to inbound connections.

## Usage

```hcl
module "nat" {
  source      = "../../modules/nat"
  project_id  = var.project_id
  region      = var.region
  router_name = module.cloud_router.router_name
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | required | GCP project ID |
| `region` | `string` | `asia-south1` | GCP region |
| `nat_name` | `string` | `platform-nat` | NAT gateway name |
| `router_name` | `string` | required | Cloud Router to attach to |
| `min_ports_per_vm` | `number` | `64` | Min NAT ports per VM |

## Outputs

| Name | Description |
|---|---|
| `nat_name` | NAT gateway name |
