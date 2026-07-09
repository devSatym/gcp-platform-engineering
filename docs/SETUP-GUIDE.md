# Platform Engineering GCP — Setup & Configuration Guide (Phases 1-6)

> **This guide takes you from a clean GCP project to a fully operational GitOps platform.**
> Follow every step in order. Do NOT skip ahead.

---

## Prerequisites

### Local Tools Required

| Tool | Version | Install Command |
|---|---|---|
| `gcloud` CLI | Latest | [Install Guide](https://cloud.google.com/sdk/docs/install) |
| `terraform` | ≥1.5 | `brew install terraform` or [Download](https://developer.hashicorp.com/terraform/downloads) |
| `kubectl` | ≥1.28 | `gcloud components install kubectl` |
| `helm` | ≥3.14 | `brew install helm` or [Install](https://helm.sh/docs/intro/install/) |
| `git` | Latest | Pre-installed on most systems |

### GCP Requirements

- A GCP project with **billing enabled**
- **Owner** or **Editor** role on the project
- GitHub repository (forked/cloned from this project)

---

## Step 0 — Initial Setup

### 0.1 — Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/project-2.git
cd project-2
```

### 0.2 — Authenticate to GCP

```bash
# Login to GCP
gcloud auth login

# Set Application Default Credentials (used by Terraform locally)
gcloud auth application-default login

# Verify
gcloud config list
```

### 0.3 — Decide your project values

You need these 3 values for everything below. Write them down:

```
GCP_PROJECT_ID = _______________   (e.g., "my-platform-project")
GITHUB_USERNAME = ______________   (e.g., "satyam-agnihotri")
GITHUB_REPO = _________________   (e.g., "satyam-agnihotri/project-2")
```

---

## Step 1 — Replace ALL Placeholders

> **This is the most critical step. Missing even one placeholder will cause `terraform apply` to fail.**

### 1.1 — Run this sed command to replace ALL occurrences at once

```bash
# Replace YOUR_USERNAME with your GitHub username
find . -type f \( -name "*.tf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.sh" \) \
  ! -path './.git/*' ! -path './.gemini/*' \
  -exec sed -i "s|YOUR_USERNAME|YOUR_ACTUAL_GITHUB_USERNAME|g" {} +

# Replace YOUR_PROJECT_ID with your GCP project ID
find . -type f \( -name "*.tf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.sh" \) \
  ! -path './.git/*' ! -path './.gemini/*' \
  -exec sed -i "s|YOUR_PROJECT_ID|YOUR_ACTUAL_GCP_PROJECT_ID|g" {} +

# Replace YOUR_GITHUB_USERNAME (in renovate.json)
find . -type f -name "*.json" \
  ! -path './.git/*' ! -path './.gemini/*' \
  -exec sed -i "s|YOUR_GITHUB_USERNAME|YOUR_ACTUAL_GITHUB_USERNAME|g" {} +

# Replace the default project ID in tfvars and bootstrap.sh
find . -type f \( -name "*.tfvars" -o -name "*.sh" \) \
  ! -path './.git/*' ! -path './.gemini/*' \
  -exec sed -i "s|platform-engineering-demo|YOUR_ACTUAL_GCP_PROJECT_ID|g" {} +
```

### 1.2 — Verify no placeholders remain

```bash
grep -rn "YOUR_USERNAME\|YOUR_PROJECT_ID\|YOUR_GITHUB_USERNAME\|platform-engineering-demo" \
  --include="*.tf" --include="*.yaml" --include="*.yml" --include="*.json" --include="*.sh" \
  . 2>/dev/null | grep -v '.git/' | grep -v '.gemini/'
```

**Expected output: nothing.** If any lines appear, fix them manually.

### 1.3 — Files that were updated (for reference)

| File | Placeholder | Replaced With |
|---|---|---|
| `terraform/environments/dev/terraform.tfvars` | `platform-engineering-demo` | Your GCP project ID |
| `terraform/environments/dev/backend.tf` | `platform-engineering-demo-tf-state` | `{your-project-id}-tf-state` |
| `terraform/environments/stage/terraform.tfvars` | Same | Same |
| `terraform/environments/prod/terraform.tfvars` | Same | Same |
| `terraform/environments/*/main.tf` (argocd_bootstrap) | `YOUR_USERNAME` | Your GitHub username |
| `terraform/environments/*/main.tf` (github_wif) | `YOUR_USERNAME` | Your GitHub username |
| `terraform/modules/argocd-bootstrap/variables.tf` | `YOUR_USERNAME` | Your GitHub username |
| `gitops/bootstrap/projects.yaml` (5 occurrences) | `YOUR_USERNAME` | Your GitHub username |
| `gitops/bootstrap/platform-appset.yaml` | `YOUR_USERNAME` | Your GitHub username |
| `gitops/bootstrap/applications-appset.yaml` | `YOUR_USERNAME` | Your GitHub username |
| `gitops/platform/external-secrets.yaml` | `YOUR_PROJECT_ID` | Your GCP project ID |
| `renovate.json` (4 occurrences) | `YOUR_GITHUB_USERNAME` | Your GitHub username |
| `bootstrap/bootstrap.sh` | `platform-engineering-demo` | Your GCP project ID |

---

## Step 2 — Fix Stage/Prod Outputs (Known Issue)

Stage and prod `outputs.tf` are missing 6 outputs that dev has. Add them:

### 2.1 — Add missing outputs to `terraform/environments/stage/outputs.tf`

Append these to the end of `stage/outputs.tf`:

```hcl
# ─── ArgoCD Bootstrap (Phase 4) ──────────────────────────────────────────────

output "argocd_access_command" {
  description = "kubectl port-forward command to access the ArgoCD UI."
  value       = module.argocd_bootstrap.argocd_access_command
}

output "argocd_password_command" {
  description = "Command to retrieve the initial ArgoCD admin password."
  value       = module.argocd_bootstrap.argocd_password_command
}

# ─── Artifact Registry (Phase 5) ─────────────────────────────────────────────

output "registry_url" {
  description = "Docker registry URL."
  value       = module.artifact_registry.registry_url
}

output "docker_auth_command" {
  description = "Run once to authenticate Docker for Artifact Registry."
  value       = module.artifact_registry.docker_auth_command
}

# ─── GitHub WIF (Phase 6) ─────────────────────────────────────────────────────

output "wif_provider" {
  description = "WIF provider name. Set as GCP_WIF_PROVIDER GitHub Actions variable."
  value       = module.github_wif.workload_identity_provider
}

output "github_actions_sa_email_wif" {
  description = "SA email for GitHub Actions WIF."
  value       = module.github_wif.github_actions_sa_email
}
```

### 2.2 — Do the same for `terraform/environments/prod/outputs.tf`

Copy the exact same block and append it to `prod/outputs.tf`.

---

## Step 3 — Run Bootstrap (Phase 1)

```bash
# Make the script executable
chmod +x bootstrap/bootstrap.sh

# Run it
./bootstrap/bootstrap.sh
```

**What this does:**
1. Enables required GCP APIs
2. Creates the Terraform state bucket: `{project-id}-tf-state`
3. Creates `sa-terraform` service account
4. Grants IAM roles to `sa-terraform`

**After bootstrap, authenticate Terraform:**

```bash
# Option A: Use Application Default Credentials (simplest for local dev)
gcloud auth application-default login

# Option B: Use SA key (traditional approach)
gcloud iam service-accounts keys create /tmp/sa-terraform-key.json \
  --iam-account=sa-terraform@YOUR_PROJECT_ID.iam.gserviceaccount.com
export GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa-terraform-key.json
```

---

## Step 4 — Terraform Apply — Dev Environment (Phases 2-6)

### 4.1 — Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

**Expected:** Successful init with GCS backend configured.

### 4.2 — Plan

```bash
terraform plan -out=dev.tfplan
```

**Review the plan carefully.** It should show ~50-80 resources to create:
- 1 VPC
- 3 subnets
- 1 Cloud Router
- 1 Cloud NAT
- 5 firewall rules
- 5 service accounts + ~15 IAM bindings
- 1 GKE cluster + 3 node pools
- 1 ArgoCD Helm release + root Application + WI bindings
- 1 Artifact Registry + 2 IAM bindings
- 1 WIF pool + 1 OIDC provider + 1 SA IAM binding

### 4.3 — Apply

```bash
terraform apply dev.tfplan
```

**This takes ~15-25 minutes** (GKE cluster creation is slow).

### 4.4 — Note the outputs

```bash
terraform output
```

**Save these outputs — you'll need them:**
```
cluster_name           = "otel-dev-gke"
get_credentials_command = "gcloud container clusters get-credentials otel-dev-gke --region asia-south1 --project YOUR_PROJECT_ID"
argocd_access_command  = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
argocd_password_command = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
registry_url           = "asia-south1-docker.pkg.dev/YOUR_PROJECT_ID/platform-docker"
wif_provider           = "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
github_actions_sa_email_wif = "sa-github-actions@YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

---

## Step 5 — Configure kubectl

```bash
# Use the command from terraform output
gcloud container clusters get-credentials otel-dev-gke \
  --region asia-south1 \
  --project YOUR_PROJECT_ID

# Verify
kubectl cluster-info
kubectl get nodes
```

**Expected:** 3-5 nodes (system pool: 1-2, general pool: 1-3).

---

## Step 6 — Verify ArgoCD (Phase 4)

### 6.1 — Access ArgoCD UI

```bash
# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open: https://localhost:8080

### 6.2 — Get admin password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Login: username `admin`, password from above.

### 6.3 — Verify ArgoCD Applications

```bash
kubectl get applications -n argocd
```

**Expected applications:**
```
NAME                     SYNC STATUS   HEALTH STATUS
root                     Synced        Healthy
platform-dev             Synced        Healthy         (or similar)
```

### 6.4 — Verify namespaces created by ArgoCD

```bash
kubectl get namespaces
```

**Expected:** argocd, platform-system, observability, security, networking, applications, otel-demo-dev, otel-demo-stage, otel-demo-prod

### 6.5 — Verify platform components

```bash
# ESO
kubectl get pods -n platform-system
# Expected: external-secrets-* pods running

# metrics-server
kubectl get pods -n kube-system | grep metrics-server
# Expected: metrics-server pods running

# PriorityClasses
kubectl get priorityclasses
# Expected: platform-critical(1000), business-critical(900), business-standard(500), non-critical(100)
```

---

## Step 7 — Verify OTel Demo (Phase 5)

### 7.1 — Check ArgoCD synced the OTel Demo

```bash
kubectl get applications -n argocd | grep otel
# Expected: otel-demo-dev (may be Synced or OutOfSync initially)
```

### 7.2 — Check OTel Demo pods

```bash
kubectl get pods -n otel-demo-dev
```

**Expected:** ~15-20 pods (all OTel Demo microservices).

If pods are in `Pending`, check:
```bash
kubectl describe pod <pod-name> -n otel-demo-dev
```

Common issue: nodes need time to scale up for the workload.

### 7.3 — Access the storefront

```bash
kubectl port-forward svc/otel-demo-frontendproxy -n otel-demo-dev 8080:8080
```

Open: http://localhost:8080 — you should see the Astronomy Shop.

### 7.4 — Access observability tools

```bash
# Grafana (admin/admin)
kubectl port-forward svc/otel-demo-grafana -n otel-demo-dev 3000:80

# Jaeger
kubectl port-forward svc/otel-demo-jaeger-query -n otel-demo-dev 16686:16686

# Prometheus
kubectl port-forward svc/otel-demo-prometheus-server -n otel-demo-dev 9090:80
```

---

## Step 8 — Verify Artifact Registry (Phase 5)

```bash
# Check the registry exists
gcloud artifacts repositories list --project=YOUR_PROJECT_ID --location=asia-south1

# Expected:
# platform-docker  DOCKER  ...  asia-south1
```

---

## Step 9 — Configure GitHub Actions (Phase 6)

### 9.1 — Push code to GitHub

```bash
git add -A
git commit -m "feat: complete platform phases 1-6"
git push origin main
```

### 9.2 — Set GitHub Actions Variables

Go to: **GitHub repo → Settings → Secrets and variables → Actions → Variables**

Add these **Variables** (not secrets — they're not sensitive):

| Variable Name | Value | Source |
|---|---|---|
| `GCP_PROJECT_ID` | Your GCP project ID | From `terraform output project_id` |
| `GCP_WIF_PROVIDER` | Full WIF provider path | From `terraform output wif_provider` |
| `GCP_SA_EMAIL` | GitHub Actions SA email | From `terraform output github_actions_sa_email_wif` |

### 9.3 — Create GitHub Environments

Go to: **GitHub repo → Settings → Environments**

Create 3 environments:
- `dev`
- `stage`
- `prod` (add required reviewers for prod)

### 9.4 — Test CI workflow

```bash
git checkout -b test/ci-validation
echo "" >> README.md
git add . && git commit -m "test: trigger CI workflow"
git push origin test/ci-validation
```

Open a PR → the `ci.yaml` workflow should trigger. Check the **Actions** tab.

### 9.5 — Verify WIF authentication works

The build and terraform workflows need WIF. Create a test PR that touches `terraform/`:

```bash
# Still on test branch
echo "# test" >> terraform/environments/dev/locals.tf
git add . && git commit -m "test: trigger terraform workflow"
git push origin test/ci-validation
```

Check the **terraform.yaml** workflow runs and authenticates to GCP.

### 9.6 — Install Renovate (optional)

Go to: https://github.com/apps/renovate → Install on your repository.
Renovate will read `renovate.json` and create automated dependency PRs.

---

## Step 10 — Deploy Stage and Prod (Optional)

Repeat Steps 4-8 for each environment:

```bash
cd terraform/environments/stage
terraform init
terraform plan -out=stage.tfplan
terraform apply stage.tfplan

cd ../prod
terraform init
terraform plan -out=prod.tfplan
terraform apply prod.tfplan
```

> **Note:** Running 3 GKE clusters simultaneously is expensive. For portfolio demonstration, dev alone is sufficient. Apply stage/prod only when needed.

---

## Verification Checklist

Run through this checklist after completing all steps:

```
[ ] GCP APIs enabled (bootstrap.sh ran successfully)
[ ] Terraform state bucket exists (gs://{project-id}-tf-state)
[ ] No placeholder text remaining in codebase
[ ] terraform apply completed for dev (no errors)
[ ] kubectl connected to cluster (kubectl get nodes works)
[ ] ArgoCD UI accessible (port-forward 8080)
[ ] ArgoCD root application is Synced + Healthy
[ ] 9 namespaces created by ArgoCD
[ ] ESO pods running in platform-system
[ ] metrics-server pods running in kube-system
[ ] 4 PriorityClasses visible (kubectl get priorityclasses)
[ ] OTel Demo pods running in otel-demo-dev
[ ] Astronomy Shop storefront accessible (port-forward)
[ ] Grafana accessible (port-forward 3000)
[ ] Artifact Registry exists (gcloud artifacts repositories list)
[ ] GitHub Actions variables set (GCP_PROJECT_ID, GCP_WIF_PROVIDER, GCP_SA_EMAIL)
[ ] CI workflow triggers on PR
[ ] Stage/prod outputs.tf fixed (6 missing outputs added)
```

---

## Cost Estimate

| Resource | Dev (monthly) | Notes |
|---|---|---|
| GKE cluster | ~$75 | Management fee |
| System pool (1× e2-medium) | ~$25 | Always-on |
| General pool (1-3× e2-standard-4) | ~$50-150 | Autoscales |
| Spot pool (0-2× e2-standard-2) | ~$5-15 | 60-91% discount |
| Cloud NAT | ~$5 | Per-gateway fee |
| Artifact Registry | ~$1 | Storage-based |
| Terraform state (GCS) | <$1 | Minimal storage |
| **Total (dev only)** | **~$160-270/month** | |

> **Cost tip:** Destroy the cluster when not in use:
> ```bash
> cd terraform/environments/dev && terraform destroy
> ```
> Re-apply when needed. ArgoCD will re-sync everything from Git automatically.

---

## Troubleshooting

### GKE cluster creation fails
- Ensure billing is enabled
- Ensure Compute Engine API and Container API are enabled
- Check quota: `gcloud compute project-info describe --project=YOUR_PROJECT_ID`

### ArgoCD shows "Unknown" or "OutOfSync"
- Wait 2-3 minutes — ArgoCD needs time to discover applications
- Check: `kubectl logs -n argocd deploy/argocd-server`
- Verify git repo URL is correct: `kubectl get applications root -n argocd -o yaml | grep repoURL`

### OTel Demo pods stuck in Pending
- Nodes may need to scale up: `kubectl get nodes` — check if general pool nodes exist
- Check events: `kubectl get events -n otel-demo-dev --sort-by=.lastTimestamp`
- Check PDB issues: `kubectl get pdb -n otel-demo-dev`

### WIF auth fails in GitHub Actions
- Verify `GCP_WIF_PROVIDER` is the full path (starts with `projects/`)
- Verify `GCP_SA_EMAIL` ends with `.iam.gserviceaccount.com`
- Verify the GitHub repo attribute condition matches exactly: `owner/repo` format

### Terraform state lock error
- Someone else may be running `terraform apply`
- Force unlock (carefully): `terraform force-unlock LOCK_ID`
