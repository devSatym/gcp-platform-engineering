# Module: cloud-router

Creates a Cloud Router that manages BGP routes for Cloud NAT.

## Purpose

Cloud Router is a prerequisite for Cloud NAT. It provides dynamic route management, allowing private GKE nodes to route outbound traffic through Cloud NAT to the internet — without having public IP addresses.

## Usage

```hcl
module "cloud_router" {
  source     = "../../modules/cloud-router"
  project_id = var.project_id
  region     = var.region
  vpc_name   = module.networking.vpc_name
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | required | GCP project ID |
| `region` | `string` | `asia-south1` | GCP region |
| `router_name` | `string` | `platform-router` | Router name |
| `vpc_name` | `string` | required | VPC to attach router to |

## Outputs

| Name | Description |
|---|---|
| `router_name` | Router name — input for nat module |
| `router_self_link` | Router self-link |
