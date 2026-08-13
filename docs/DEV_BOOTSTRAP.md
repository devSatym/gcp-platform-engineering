# Dev environment bootstrap

The dev environment has one intentional control point: a reviewed Terraform
apply. After that apply starts, Terraform installs Argo CD, creates the root
Application, and waits for every generated platform/workload Application to be
`Synced` and `Healthy`. Argo CD then continuously reconciles the cluster from
Git. No manual Helm, `kubectl apply`, or Argo CD sync commands are required.

## One-time prerequisites

Authenticate using Application Default Credentials or Workload Identity
Federation; do not create a service-account key.

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"

gcloud auth application-default login
./bootstrap/bootstrap.sh "$GCP_PROJECT_ID" "$GCP_REGION"
```

Configure the environment-owned values before the first deployment:

- `terraform/environments/dev/terraform.tfvars`
- `gitops/environments/dev/config.yaml`

## Deploy

```bash
cd terraform/environments/dev
terraform init -input=false -backend-config="bucket=${GCP_PROJECT_ID}-tfstate"
terraform validate
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

Terraform does not finish successfully until the GitOps convergence gate has
verified all generated Applications. The root Application also runs an
authenticated post-sync check that confirms Grafana has imported all five
platform dashboards.

## Verify or access locally

The readiness check can be run again without changing cluster state:

```bash
scripts/wait-for-gitops-convergence.sh --environment dev --timeout 1800
```

Expose local-only UIs when needed:

```bash
scripts/expose-platform-uis.sh
```

Grafana is available at `http://127.0.0.1:3000`; fetch runtime credentials
only when needed with `scripts/get-dashboard-credentials.sh --show-secrets`.
