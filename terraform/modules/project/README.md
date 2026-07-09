# Module: project

Enables all required GCP APIs for the platform engineering project.

## Purpose

This module must be applied **first** — every other module depends on the APIs it enables. It uses `for_each` over a list of service names so new APIs can be added easily without duplicating resource blocks.

`disable_on_destroy = false` is intentional: disabling APIs during `terraform destroy` can interfere with other resources and takes time to re-enable. APIs are cheap and safe to leave enabled.

## Usage

```hcl
module "project" {
  source     = "../../modules/project"
  project_id = var.project_id
  labels     = local.labels
}
```

## APIs Enabled

| API | Phase | Purpose |
|---|---|---|
| `compute.googleapis.com` | 2 | VPC, subnets, firewall, NAT |
| `cloudresourcemanager.googleapis.com` | 2 | Project and IAM management |
| `iam.googleapis.com` | 2 | Service accounts |
| `storage.googleapis.com` | 2 | Terraform state bucket |
| `iamcredentials.googleapis.com` | 2 | Workload Identity Federation |
| `sts.googleapis.com` | 2 | Security Token Service |
| `container.googleapis.com` | 3 | GKE |
| `artifactregistry.googleapis.com` | 5 | Container image registry |
| `dns.googleapis.com` | 5 | Cloud DNS |
| `secretmanager.googleapis.com` | 6 | Secret storage |
| `binaryauthorization.googleapis.com` | 7 | Image deployment policies |
| `containeranalysis.googleapis.com` | 7 | Vulnerability analysis |
| `containerscanning.googleapis.com` | 7 | Container scanning |
| `logging.googleapis.com` | 8 | Cloud Logging |
| `monitoring.googleapis.com` | 8 | Cloud Monitoring |
| `cloudtrace.googleapis.com` | 8 | Distributed tracing |
| `gkebackup.googleapis.com` | 14 | GKE Backup |

## Inputs

| Name | Type | Description |
|---|---|---|
| `project_id` | `string` | GCP project ID |
| `labels` | `map(string)` | Labels for project-level resources |

## Outputs

| Name | Description |
|---|---|
| `project_id` | Pass-through project ID for downstream modules |
| `enabled_apis` | List of enabled API services |
