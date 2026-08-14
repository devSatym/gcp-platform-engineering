# Continuous integration and GitOps verification

This repository has three non-mutating GitHub Actions workflows:

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `CI — Platform Validation` | Pull requests and pushes to `main` | Lints and renders GitOps, validates shell scripts and Terraform, blocks leaked credentials, and reports Terraform security findings. |
| `Terraform Plan` | Manual dispatch | Produces a reviewed plan for the selected environment. It never runs `terraform apply`. |
| `Dev GitOps Verification` | GitOps changes merged to `main` and manual dispatch | Waits for Argo CD convergence and runs the read-only dev workload preflight. |

Image builds, SBOM generation, image scanning, and signing remain in the
separate Supply Chain Security workflow. CI blocks credential leaks with
Gitleaks and reports Terraform security findings with Checkov.

## One-time GitHub configuration

Create repository or `dev` environment variables in **Settings → Secrets and
variables → Actions**. None of these values are credentials.

| Variable | Source |
| --- | --- |
| `GCP_PROJECT_ID` | `platform_config.project_id` in `terraform/environments/dev/terraform.tfvars` |
| `GKE_CLUSTER_NAME` | `platform_config.cluster_name` in `terraform/environments/dev/terraform.tfvars` |
| `GKE_CLUSTER_LOCATION` | `terraform output -json platform \| jq -r '.cluster_location'` from `terraform/environments/dev` |
| `TF_STATE_BUCKET` | `${GCP_PROJECT_ID}-tfstate`, created by `bootstrap/bootstrap.sh` |
| `GCP_WIF_PROVIDER` | `terraform output -json platform \| jq -r '.wif_provider'` from `terraform/environments/dev` |
| `GCP_SA_EMAIL` | `terraform output -json platform \| jq -r '.github_actions_sa_email'` from `terraform/environments/dev` |

The GitHub Actions service account must be able to read the GKE resources that
the post-deploy check inspects. Grant the platform's existing GitHub Actions
identity the least-privilege GKE viewer role through reviewed Terraform before
enabling the post-deploy workflow.

## Optional Terraform plan identity

`Terraform Plan` is manually dispatched because it reads live cloud resources
and remote Terraform state. Before using it, ensure the WIF service account
named by `GCP_SA_EMAIL` has read access to the relevant GCP resources and the
`TF_STATE_BUCKET`. The workflow does not run an apply, and it should not be
given mutation permissions merely to create a plan.

Create a GitHub environment named `dev`. Do not add required reviewers to this
environment if post-merge dev verification should run automatically. Protect
`main` and require the `CI Complete` status check before merging pull requests.

## Intentional manual control point

Terraform applies remain manual and reviewed:

```bash
cd terraform/environments/dev
terraform init -input=false -backend-config="bucket=${GCP_PROJECT_ID}-tfstate"
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

After a GitOps merge, Argo CD deploys automatically and the post-deploy
workflow verifies convergence. The optional payment-failure demonstration and
browser dashboard inspection remain manual because they deliberately alter
runtime behaviour or require local-only UI access.
