# Bootstrap — One-Time GCP Setup

This script must be run **once** before any `terraform apply`. It creates two resources that Terraform cannot bootstrap itself:

1. A GCS bucket to store Terraform remote state
2. A `sa-terraform` service account with the permissions Terraform needs to manage the project

---

## Prerequisites

- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- Billing enabled on your GCP project
- Owner or Editor rights on the project

---

## How to Run

```bash
# 1. Edit PROJECT_ID in bootstrap.sh
vim bootstrap/bootstrap.sh

# 2. Make executable and run
chmod +x bootstrap/bootstrap.sh
./bootstrap/bootstrap.sh

# 3. Follow the printed instructions to download the sa-terraform key
#    and configure gcloud / Terraform
```

---

## What It Creates

| Resource | Name | Purpose |
|---|---|---|
| GCS Bucket | `{PROJECT_ID}-tfstate` | Remote Terraform state |
| Service Account | `sa-terraform@{PROJECT_ID}.iam.gserviceaccount.com` | Terraform execution identity |
| IAM Binding | `scoped infrastructure IAM roles` | Terraform resource management |
| IAM Binding | `roles/resourcemanager.projectIamAdmin` | Terraform IAM management |

---

## After Bootstrap

Update the following files with your project ID:

- `terraform/environments/dev/terraform.tfvars` → set `project_id`
- `terraform/environments/dev/backend.tf` → set `bucket`
- `terraform/environments/staging/terraform.tfvars` + `backend.tf`
- `terraform/environments/prod/terraform.tfvars` + `backend.tf`

---

## Cleanup

If you tear down the entire project:

```bash
# Delete state bucket (CAUTION: this destroys all Terraform state)
gsutil rm -r gs://${PROJECT_ID}-tfstate

# Delete service account
gcloud iam service-accounts delete sa-terraform@${PROJECT_ID}.iam.gserviceaccount.com
```
