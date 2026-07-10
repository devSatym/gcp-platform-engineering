# GCP Platform Engineering — Complete Setup Guide (Phases 1–6)

> **This guide takes you from zero to a fully running GitOps platform on GCP.**
> Follow every step in order. Each section shows the exact command, what it does, and the expected output.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 0 — Clone & Configure](#step-0--clone--configure)
3. [Step 1 — Replace All Placeholders](#step-1--replace-all-placeholders)
4. [Step 2 — Bootstrap (Phase 1)](#step-2--bootstrap-phase-1)
5. [Step 3 — Terraform Apply Dev (Phases 2–6)](#step-3--terraform-apply-dev-phases-26)
6. [Step 4 — Connect kubectl](#step-4--connect-kubectl)
7. [Step 5 — Verify ArgoCD (Phase 4)](#step-5--verify-argocd-phase-4)
8. [Step 6 — Verify Platform Components](#step-6--verify-platform-components)
9. [Step 7 — Verify OTel Demo (Phase 5)](#step-7--verify-otel-demo-phase-5)
10. [Step 8 — Configure GitHub Actions (Phase 6)](#step-8--configure-github-actions-phase-6)
11. [Step 9 — Deploy Stage & Prod](#step-9--deploy-stage--prod)
12. [Verification Checklist](#verification-checklist)
13. [Cost Estimate](#cost-estimate)
14. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### 1. Local Tools

Install these before starting:

| Tool | Min Version | Install |
|---|---|---|
| `gcloud` CLI | Latest | [cloud.google.com/sdk/docs/install](https://cloud.google.com/sdk/docs/install) |
| `terraform` | ≥ 1.5 | `sudo apt install terraform` or [Download](https://developer.hashicorp.com/terraform/install) |
| `kubectl` | ≥ 1.28 | `gcloud components install kubectl` |
| `helm` | ≥ 3.14 | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash` |
| `git` | Latest | Pre-installed on most systems |

**Verify all tools are installed:**
```bash
gcloud version | head -1
terraform version | head -1
kubectl version --client --short 2>/dev/null || kubectl version --client
helm version --short
git --version
```

**Expected output (versions may differ):**
```
Google Cloud SDK 480.0.0
Terraform v1.9.0
Client Version: v1.29.0
v3.15.0+g4484e46
git version 2.43.0
```

---

### 2. GCP Requirements

- A GCP project with **billing enabled**
- Your account must have **Owner** or **Editor** + **Project IAM Admin** roles
- A **GitHub account** with a repository for this project

---

### 3. Collect Your Values

You need these 3 values before starting. Keep them handy throughout this guide:

```
GCP_PROJECT_ID  = _______________   # e.g. "my-platform-prod-12345"
GITHUB_USERNAME = _______________   # e.g. "devSatym"
GITHUB_REPO     = _______________   # e.g. "devSatym/gcp-platform-engineering"
```

---

## Step 0 — Clone & Configure

### 0.1 — Clone the repository

```bash
git clone https://github.com/devSatym/gcp-platform-engineering.git
cd gcp-platform-engineering
```

**Expected output:**
```
Cloning into 'gcp-platform-engineering'...
remote: Enumerating objects: 312, done.
...
```

---

### 0.2 — Authenticate to GCP

```bash
# Login with your user account
gcloud auth login

# Set Application Default Credentials (used by Terraform locally)
gcloud auth application-default login

# Set your project
gcloud config set project YOUR_GCP_PROJECT_ID
```

**Verify authentication:**
```bash
gcloud config list
```

**Expected output:**
```
[core]
account = your-email@gmail.com
project = your-gcp-project-id

[compute]
region = asia-south1
```

---

## Step 1 — Replace All Placeholders

> ⚠️ **Critical step.** The codebase still contains `platform-engineering-demo` as the default project ID in `terraform.tfvars` and `backend.tf`. You must replace it before running any Terraform command.

### 1.1 — Run the replacement commands

```bash
export GCP_PROJECT_ID="your-actual-gcp-project-id"   # <-- set this first
export GITHUB_USERNAME="your-github-username"          # <-- set this first

# Replace default project ID in tfvars and backend files
find . -type f \( -name "*.tfvars" -o -name "*.tf" \) \
  ! -path './.git/*' ! -path './.terraform/*' \
  -exec sed -i "s|platform-engineering-demo|${GCP_PROJECT_ID}|g" {} +

# Replace YOUR_GCP_PROJECT_ID in gitops manifests
find . -type f -name "*.yaml" \
  ! -path './.git/*' \
  -exec sed -i "s|YOUR_GCP_PROJECT_ID|${GCP_PROJECT_ID}|g" {} +

# Replace YOUR_GITHUB_USERNAME in renovate.json
sed -i "s|YOUR_GITHUB_USERNAME|${GITHUB_USERNAME}|g" renovate.json
```

### 1.2 — Verify no placeholders remain

```bash
grep -rn "platform-engineering-demo\|YOUR_GCP_PROJECT_ID\|YOUR_GITHUB_USERNAME" \
  --include="*.tf" --include="*.yaml" --include="*.json" --include="*.sh" \
  . 2>/dev/null | grep -v '.git/'
```

**Expected output: nothing.** If any lines appear, fix them manually before continuing.

### 1.3 — What was updated

| File | Placeholder | New Value |
|---|---|---|
| `terraform/environments/dev/terraform.tfvars` | `platform-engineering-demo` | Your GCP project ID |
| `terraform/environments/stage/terraform.tfvars` | `platform-engineering-demo` | Your GCP project ID |
| `terraform/environments/prod/terraform.tfvars` | `platform-engineering-demo` | Your GCP project ID |
| `terraform/environments/dev/backend.tf` | `platform-engineering-demo-tf-state` | `{project-id}-tf-state` |
| `terraform/environments/stage/backend.tf` | Same | Same |
| `terraform/environments/prod/backend.tf` | Same | Same |
| `gitops/platform/external-secrets.yaml` | `YOUR_GCP_PROJECT_ID` | Your GCP project ID |
| `renovate.json` | `YOUR_GITHUB_USERNAME` | Your GitHub username |

> **Note:** `YOUR_USERNAME` in `main.tf` files and `YOUR_USERNAME` in GitOps YAMLs were already replaced with `devSatym/gcp-platform-engineering` during the code audit. Only the tfvars/backend project-ID placeholders remain for you to update.

---

## Step 2 — Bootstrap (Phase 1)

The bootstrap script creates the Terraform state bucket and Terraform service account in one shot.

### 2.1 — Run bootstrap

```bash
chmod +x bootstrap/bootstrap.sh
./bootstrap/bootstrap.sh
```

**Expected output:**
```
═══════════════════════════════════════════════════════════════
Bootstrap starting for project: your-gcp-project-id
═══════════════════════════════════════════════════════════════

[INFO] Step 1/4: Enabling required GCP APIs...
[SUCCESS] APIs enabled.

[INFO] Step 2/4: Creating Terraform state bucket: your-gcp-project-id-tf-state
[SUCCESS] Bucket created: gs://your-gcp-project-id-tf-state

[INFO] Step 3/4: Creating Terraform service account: sa-terraform@...
[SUCCESS] Service account created: sa-terraform@your-gcp-project-id.iam.gserviceaccount.com

[INFO] Step 4/4: Granting IAM roles to Terraform SA...
[SUCCESS] IAM roles granted.

═══════════════════════════════════════════════════════════════
Bootstrap complete!
═══════════════════════════════════════════════════════════════
```

### 2.2 — Verify the state bucket was created

```bash
gsutil ls gs://${GCP_PROJECT_ID}-tf-state
```

**Expected output:**
```
# (empty — bucket exists but has no state files yet)
```

### 2.3 — Authenticate Terraform

For local development, Application Default Credentials is simplest:

```bash
gcloud auth application-default login
```

**Expected output:**
```
Your browser has been opened to visit:
  https://accounts.google.com/o/oauth2/auth?...

Credentials saved to file: [/home/user/.config/gcloud/application_default_credentials.json]
```

---

## Step 3 — Terraform Apply Dev (Phases 2–6)

> This single `terraform apply` creates everything: VPC, GKE, ArgoCD, Artifact Registry, and WIF. It takes **15–25 minutes** (GKE cluster creation is the slow step).

### 3.1 — Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

**Expected output:**
```
Initializing modules...
- argocd_bootstrap in ../../modules/argocd-bootstrap
- artifact_registry in ../../modules/artifact-registry
- cloud_router in ../../modules/cloud-router
- firewall in ../../modules/firewall
- github_wif in ../../modules/github-wif
- gke in ../../modules/gke
- nat in ../../modules/nat
- networking in ../../modules/networking
- project in ../../modules/project
- service_accounts in ../../modules/service-accounts

Initializing the backend...
Successfully configured the backend "gcs"!

Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 5.0"...
- Finding hashicorp/helm versions matching "~> 2.12"...
- Finding hashicorp/kubernetes versions matching "~> 2.27"...
- Installed hashicorp/google v5.x.x
- Installed hashicorp/helm v2.x.x
- Installed hashicorp/kubernetes v2.x.x

Terraform has been successfully initialized!
```

> ❌ **If init fails with "bucket not found":** Run `./bootstrap/bootstrap.sh` first (Step 2).
> ❌ **If init fails with "provider not found":** Ensure `versions.tf` has `helm` and `kubernetes` in `required_providers`.

---

### 3.2 — Validate configuration

```bash
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

> ❌ **If validate fails:** Review the error message. Common causes are listed in the [Troubleshooting](#troubleshooting) section.

---

### 3.3 — Plan

```bash
terraform plan -out=dev.tfplan 2>&1 | tee plan-output.txt
```

**Expected output (summary):**
```
Plan: 65 to add, 0 to change, 0 to destroy.

Resources being created:
  + module.networking.google_compute_network.vpc
  + module.networking.google_compute_subnetwork.gke_subnet
  + module.networking.google_compute_subnetwork.management_subnet
  + module.networking.google_compute_subnetwork.proxy_subnet
  + module.cloud_router.google_compute_router.router
  + module.nat.google_compute_router_nat.nat
  + module.firewall.google_compute_firewall.allow_internal
  + module.firewall.google_compute_firewall.allow_iap_ssh
  + module.firewall.google_compute_firewall.allow_health_checks
  + module.firewall.google_compute_firewall.deny_all_ingress
  + module.service_accounts.google_service_account.gke_nodes  (+ 4 more SAs)
  + module.gke.google_container_cluster.primary
  + module.gke.google_container_node_pool.system
  + module.gke.google_container_node_pool.general
  + module.gke.google_container_node_pool.spot
  + module.argocd_bootstrap.helm_release.argocd
  + module.argocd_bootstrap.kubernetes_manifest.root_application
  + module.argocd_bootstrap.google_service_account_iam_member.argocd_wi  (+ 2 more WI bindings)
  + module.artifact_registry.google_artifact_registry_repository.docker
  + module.github_wif.google_iam_workload_identity_pool.github_pool
  + module.github_wif.google_iam_workload_identity_pool_provider.github
  ... (and more IAM bindings, API enablements)
```

**Review the plan output.** Confirm you see ~60-70 resources to add and **0 to destroy**.

---

### 3.4 — Apply

```bash
terraform apply dev.tfplan
```

**Expected output (abbreviated):**
```
module.project.google_project_service.apis["container.googleapis.com"]: Creating...
module.networking.google_compute_network.vpc: Creating...
...
module.gke.google_container_cluster.primary: Still creating... [5m0s elapsed]
module.gke.google_container_cluster.primary: Still creating... [10m0s elapsed]
module.gke.google_container_cluster.primary: Creation complete after 14m32s
...
module.argocd_bootstrap.helm_release.argocd: Still creating... [3m0s elapsed]
module.argocd_bootstrap.helm_release.argocd: Creation complete after 4m15s
module.argocd_bootstrap.kubernetes_manifest.root_application: Creating...
module.argocd_bootstrap.kubernetes_manifest.root_application: Creation complete after 8s

Apply complete! Resources: 65 added, 0 changed, 0 destroyed.
```

> ⏱️ **Total time: ~15–25 minutes.** This is normal — GKE cluster creation takes 10–15 minutes alone.

---

### 3.5 — Save the outputs

```bash
terraform output
```

**Expected output:**
```
argocd_access_command      = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
argocd_password_command    = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
cluster_location           = "asia-south1"
cluster_name               = "otel-dev-gke"
docker_auth_command        = "gcloud auth configure-docker asia-south1-docker.pkg.dev"
get_credentials_command    = "gcloud container clusters get-credentials otel-dev-gke --region=asia-south1 --project=your-project-id"
github_actions_sa_email_wif = "sa-github-actions@your-project-id.iam.gserviceaccount.com"
nat_name                   = "platform-nat"
registry_url               = "asia-south1-docker.pkg.dev/your-project-id/platform-docker"
router_name                = "platform-router"
vpc_name                   = "platform-vpc"
wif_provider               = "projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
workload_identity_pool     = "your-project-id.svc.id.goog"
```

> 📋 **Copy these outputs** — you'll need `wif_provider` and `github_actions_sa_email_wif` for GitHub Actions in Step 8.

---

## Step 4 — Connect kubectl

### 4.1 — Get cluster credentials

```bash
gcloud container clusters get-credentials otel-dev-gke \
  --region asia-south1 \
  --project ${GCP_PROJECT_ID}
```

**Expected output:**
```
Fetching cluster endpoint and auth data.
kubeconfig entry generated for otel-dev-gke.
```

### 4.2 — Verify nodes are ready

```bash
kubectl get nodes -o wide
```

**Expected output:**
```
NAME                                         STATUS   ROLES    AGE   VERSION
gke-otel-dev-gke-system-pool-xxx-yyy         Ready    <none>   5m    v1.29.x-gke.xxx
gke-otel-dev-gke-general-pool-xxx-zzz        Ready    <none>   4m    v1.29.x-gke.xxx
```

> You should see at least 2 nodes (1 system, 1 general). The spot pool starts at 0 nodes.

### 4.3 — Verify cluster info

```bash
kubectl cluster-info
```

**Expected output:**
```
Kubernetes control plane is running at https://XX.XX.XX.XX
GLBCDefaultBackend is running at https://XX.XX.XX.XX/api/v1/namespaces/kube-system/services/...
```

---

## Step 5 — Verify ArgoCD (Phase 4)

### 5.1 — Check ArgoCD pods are running

```bash
kubectl get pods -n argocd
```

**Expected output:**
```
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          5m
argocd-applicationset-controller-xxx-yyy            1/1     Running   0          5m
argocd-dex-server-xxx-yyy                           1/1     Running   0          5m
argocd-notifications-controller-xxx-yyy             1/1     Running   0          5m
argocd-redis-xxx-yyy                                1/1     Running   0          5m
argocd-repo-server-xxx-yyy                          1/1     Running   0          5m
argocd-server-xxx-yyy                               1/1     Running   0          5m
```

> ❌ **If pods show `CrashLoopBackOff`:** Check logs with `kubectl logs -n argocd deploy/argocd-server`.

---

### 5.2 — Port-forward to the ArgoCD UI

```bash
# Run in a separate terminal (or background with &)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

Open your browser: **https://localhost:8080**

> Accept the self-signed certificate warning (click "Advanced" → "Proceed").

---

### 5.3 — Get admin password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

**Expected output:**
```
xK9mP3qRt8vW2nLs   # (random string — yours will differ)
```

Login to the UI: **Username:** `admin` | **Password:** output from above.

---

### 5.4 — Verify the root Application is synced

```bash
kubectl get applications -n argocd
```

**Expected output (after 2–3 minutes):**
```
NAME           SYNC STATUS   HEALTH STATUS   OPERATION
root           Synced        Healthy
```

> ⏱️ **Wait up to 5 minutes** for ArgoCD to discover and sync child applications after the root app is created.

If `root` shows `OutOfSync` or `Unknown`:
```bash
# Check what ArgoCD sees
kubectl get application root -n argocd -o yaml | grep -A5 "status:"

# Check ArgoCD server logs
kubectl logs -n argocd deploy/argocd-server --tail=50
```

---

### 5.5 — Verify child applications appear

After the root application syncs, it discovers all apps in `gitops/bootstrap/`:

```bash
kubectl get applications -n argocd
```

**Expected output (after ~5 minutes):**
```
NAME                          SYNC STATUS   HEALTH STATUS
root                          Synced        Healthy
external-secrets-operator     Synced        Healthy
metrics-server                Synced        Healthy
platform-dev                  Synced        Healthy
otel-demo-dev                 Synced        Progressing   # (deploying OTel demo)
```

---

## Step 6 — Verify Platform Components

### 6.1 — Check namespaces were created by ArgoCD

```bash
kubectl get namespaces
```

**Expected output (9 namespaces from `gitops/bootstrap/namespaces.yaml`):**
```
NAME              STATUS   AGE
argocd            Active   10m
applications      Active   5m
default           Active   15m
kube-system       Active   15m
networking        Active   5m
observability     Active   5m
otel-demo-dev     Active   5m
otel-demo-prod    Active   5m
otel-demo-stage   Active   5m
platform-system   Active   5m
security          Active   5m
```

> ❌ **If namespaces are missing:** Check `kubectl get application root -n argocd -o yaml | grep -A10 conditions`.

---

### 6.2 — Verify External Secrets Operator

```bash
kubectl get pods -n platform-system
```

**Expected output:**
```
NAME                                                READY   STATUS    RESTARTS   AGE
external-secrets-xxxxx-yyy                          1/1     Running   0          5m
external-secrets-cert-controller-xxxxx-yyy          1/1     Running   0          5m
external-secrets-webhook-xxxxx-yyy                  1/1     Running   0          5m
```

**Verify CRDs were installed:**
```bash
kubectl get crd | grep external-secrets
```

**Expected output:**
```
clustersecretstores.external-secrets.io    2024-xx-xx
externalsecrets.external-secrets.io        2024-xx-xx
secretstores.external-secrets.io           2024-xx-xx
```

---

### 6.3 — Verify Metrics Server

```bash
kubectl get pods -n kube-system | grep metrics-server
```

**Expected output:**
```
metrics-server-xxxxx-yyy   1/1   Running   0   5m
```

**Test metrics are working:**
```bash
kubectl top nodes
```

**Expected output:**
```
NAME                                    CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
gke-otel-dev-gke-system-pool-xxx        150m         7%     890Mi           45%
gke-otel-dev-gke-general-pool-xxx       80m          2%     620Mi           10%
```

> ❌ **If `kubectl top nodes` returns `error: Metrics API not available`:** Wait 2 minutes for the metrics server to initialize.

---

### 6.4 — Verify PriorityClasses

```bash
kubectl get priorityclasses
```

**Expected output:**
```
NAME                      VALUE        GLOBAL-DEFAULT   AGE
business-critical         900          false            5m
business-standard         500          true             5m
non-critical              100          false            5m
platform-critical         1000         false            5m
system-cluster-critical   2000000000   false            15m
system-node-critical      2000001000   false            15m
```

---

### 6.5 — Verify ArgoCD Projects

```bash
kubectl get appprojects -n argocd
```

**Expected output:**
```
NAME           AGE
applications   5m
default        15m
networking     5m
observability  5m
platform       5m
security       5m
```

---

## Step 7 — Verify OTel Demo (Phase 5)

### 7.1 — Check OTel Demo pods

```bash
kubectl get pods -n otel-demo-dev
```

**Expected output (~20 pods):**
```
NAME                                         READY   STATUS    RESTARTS   AGE
otel-demo-accountingservice-xxxxx            1/1     Running   0          5m
otel-demo-adservice-xxxxx                    1/1     Running   0          5m
otel-demo-cartservice-xxxxx                  1/1     Running   0          5m
otel-demo-checkoutservice-xxxxx              1/1     Running   0          5m
otel-demo-currencyservice-xxxxx              1/1     Running   0          5m
otel-demo-emailservice-xxxxx                 1/1     Running   0          5m
otel-demo-frauddetectionservice-xxxxx        1/1     Running   0          5m
otel-demo-frontend-xxxxx                     1/1     Running   0          5m
otel-demo-frontendproxy-xxxxx                1/1     Running   0          5m
otel-demo-grafana-xxxxx                      1/1     Running   0          5m
otel-demo-jaeger-xxxxx                       1/1     Running   0          5m
otel-demo-loadgenerator-xxxxx                1/1     Running   0          5m
otel-demo-otelcol-xxxxx                      1/1     Running   0          5m
otel-demo-paymentservice-xxxxx               1/1     Running   0          5m
otel-demo-productcatalogservice-xxxxx        1/1     Running   0          5m
otel-demo-prometheus-server-xxxxx            1/1     Running   0          5m
otel-demo-quoteservice-xxxxx                 1/1     Running   0          5m
otel-demo-recommendationservice-xxxxx        1/1     Running   0          5m
otel-demo-shippingservice-xxxxx              1/1     Running   0          5m
```

> ⏱️ **First deployment takes 5–10 minutes** as nodes scale up and images pull.

> ❌ **If pods are `Pending`:** Check `kubectl describe pod <pod-name> -n otel-demo-dev`. Most likely cause: nodes need to scale up. Wait 3–5 minutes.

---

### 7.2 — Access the Astronomy Shop storefront

```bash
kubectl port-forward svc/otel-demo-frontendproxy -n otel-demo-dev 8090:8080
```

Open: **http://localhost:8090**

You should see the **OpenTelemetry Astronomy Shop** — a fully functioning e-commerce demo with a telescope/star catalog.

---

### 7.3 — Access observability tools

```bash
# Grafana — dashboards for OTel metrics (user: admin, pass: admin)
kubectl port-forward svc/otel-demo-grafana -n otel-demo-dev 3000:80

# Jaeger — distributed tracing UI
kubectl port-forward svc/otel-demo-jaeger-query -n otel-demo-dev 16686:16686

# Prometheus — raw metrics
kubectl port-forward svc/otel-demo-prometheus-server -n otel-demo-dev 9090:80
```

| Tool | URL |
|---|---|
| Astronomy Shop | http://localhost:8090 |
| Grafana | http://localhost:3000 |
| Jaeger | http://localhost:16686 |
| Prometheus | http://localhost:9090 |

---

### 7.4 — Verify Artifact Registry

```bash
gcloud artifacts repositories list \
  --project=${GCP_PROJECT_ID} \
  --location=asia-south1
```

**Expected output:**
```
REPOSITORY       FORMAT  MODE                 DESCRIPTION                      LOCATION     LABELS  ENCRYPTION  CREATE_TIME
platform-docker  DOCKER  STANDARD_REPOSITORY  Private Docker registry for...   asia-south1          Google-managed
```

---

## Step 8 — Configure GitHub Actions (Phase 6)

### 8.1 — Get WIF values from Terraform output

```bash
cd terraform/environments/dev

# Get the WIF provider path
terraform output -raw wif_provider
# Example: projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-provider

# Get the GitHub Actions SA email
terraform output -raw github_actions_sa_email_wif
# Example: sa-github-actions@your-project-id.iam.gserviceaccount.com

# Get project ID
terraform output -raw project_id
```

---

### 8.2 — Set GitHub Actions Variables

Go to: **GitHub repo → Settings → Secrets and variables → Actions → Variables tab**

Click **"New repository variable"** for each:

| Variable Name | Value | Where to get it |
|---|---|---|
| `GCP_PROJECT_ID` | `your-gcp-project-id` | `terraform output -raw project_id` |
| `GCP_WIF_PROVIDER` | `projects/NUMBER/locations/global/...` | `terraform output -raw wif_provider` |
| `GCP_SA_EMAIL` | `sa-github-actions@....iam.gserviceaccount.com` | `terraform output -raw github_actions_sa_email_wif` |

> ⚠️ These are **Variables** (not Secrets) — they are not sensitive values. Do NOT put them in Secrets.

---

### 8.3 — Create GitHub Environments

Go to: **GitHub repo → Settings → Environments → New environment**

Create these 3 environments exactly:

| Environment Name | Protection Rules |
|---|---|
| `dev` | None (auto-deploy) |
| `stage` | Optional: require manual approval |
| `prod` | **Recommended:** require 1 reviewer before deploy |

---

### 8.4 — Test CI workflow

```bash
# Create a test branch
git checkout -b test/verify-ci

# Make a harmless change
echo "" >> README.md
git add README.md
git commit -m "test: verify CI workflow triggers"
git push origin test/verify-ci
```

Open a Pull Request on GitHub.

Go to: **GitHub repo → Actions tab**

**Expected:** The `CI` workflow (`ci.yaml`) triggers automatically and shows:
```
✓ yamllint
✓ Helm lint
✓ Terraform fmt check
✓ Terraform validate
✓ Checkov security scan
✓ Gitleaks secret scan
```

---

### 8.5 — Test Terraform Plan workflow

While the PR is open (touching any `terraform/` file):

```bash
# Still on test branch
echo "# CI test" >> terraform/environments/dev/locals.tf
git add terraform/environments/dev/locals.tf
git commit -m "test: trigger terraform plan workflow"
git push origin test/verify-ci
```

Go to: **GitHub repo → Actions tab**

**Expected:** The `Terraform` workflow triggers and:
1. Runs `terraform fmt` check
2. Runs `terraform validate` on all 3 environments
3. Posts a plan summary as a PR comment

> ❌ **If WIF auth fails:** Double-check `GCP_WIF_PROVIDER` starts with `projects/` and is the full path.

---

### 8.6 — Cleanup test branch

```bash
git checkout main
git branch -D test/verify-ci
git push origin --delete test/verify-ci
```

---

## Step 9 — Deploy Stage & Prod

> ⚠️ **Cost warning:** Running 3 GKE clusters simultaneously costs ~$480–800/month. Only deploy stage/prod when needed for load testing or pre-production validation.

### 9.1 — Deploy Stage

```bash
cd terraform/environments/stage
terraform init
terraform plan -out=stage.tfplan
terraform apply stage.tfplan
```

**Expected:** Same as dev — ~15–25 minutes, ~65 resources created.

After apply:
```bash
# Connect to stage cluster
gcloud container clusters get-credentials otel-stage-gke \
  --region asia-south1 --project ${GCP_PROJECT_ID}
```

---

### 9.2 — Deploy Prod

```bash
cd terraform/environments/prod
terraform init
terraform plan -out=prod.tfplan
terraform apply prod.tfplan
```

> **Note:** Prod uses `enable_private_endpoint = true` — the API server is only accessible from within the VPC. You'll need Cloud Shell or an IAP tunnel for `kubectl` access in prod.

**Access prod cluster via Cloud Shell:**
```bash
# In GCP Cloud Shell
gcloud container clusters get-credentials otel-prod-gke \
  --region asia-south1 --project YOUR_PROJECT_ID
kubectl get nodes
```

---

## Verification Checklist

Run through this after completing all steps:

```
Infrastructure
[ ] bootstrap.sh ran successfully
[ ] GCS state bucket exists: gs://{project-id}-tf-state
[ ] terraform apply completed for dev (no errors, ~65 resources)
[ ] No placeholder text remaining in codebase

Cluster
[ ] kubectl get nodes shows 2+ Ready nodes
[ ] kubectl cluster-info returns the API server endpoint

ArgoCD
[ ] kubectl get pods -n argocd shows 7 Running pods
[ ] ArgoCD UI accessible at https://localhost:8080
[ ] root application: Synced + Healthy
[ ] 9 namespaces created by ArgoCD

Platform Components
[ ] external-secrets pods running in platform-system
[ ] metrics-server pod running in kube-system
[ ] kubectl top nodes returns metrics
[ ] 4 custom PriorityClasses visible

OTel Demo
[ ] ~20 pods Running in otel-demo-dev
[ ] Astronomy Shop accessible at http://localhost:8090
[ ] Grafana accessible at http://localhost:3000

CI/CD
[ ] Artifact Registry: platform-docker exists
[ ] GitHub Actions variables set (GCP_PROJECT_ID, GCP_WIF_PROVIDER, GCP_SA_EMAIL)
[ ] 3 GitHub Environments created (dev, stage, prod)
[ ] CI workflow passes on PR
[ ] Terraform workflow posts plan comment on PR
```

---

## Cost Estimate

| Resource | Dev (monthly est.) | Notes |
|---|---|---|
| GKE cluster management fee | ~$74 | Per-cluster fee |
| System pool (1× e2-medium) | ~$25 | Always running |
| General pool (1–3× e2-standard-4) | ~$50–150 | Autoscales with load |
| Spot pool (0–2× e2-standard-2) | ~$0–15 | Scales to zero when idle |
| Cloud NAT | ~$5 | Per-gateway/month |
| Artifact Registry | ~$1 | Storage-based |
| Terraform state (GCS) | < $1 | Minimal |
| **Total (dev only)** | **~$160–270/month** | |
| **Total (dev+stage+prod)** | **~$480–810/month** | All 3 clusters |

**💡 Cost tip — destroy when not in use:**
```bash
# Destroy dev to stop billing
cd terraform/environments/dev && terraform destroy

# Re-apply when needed (ArgoCD re-syncs everything from Git automatically)
terraform apply dev.tfplan
```

---

## Troubleshooting

### `terraform init` fails — bucket not found
```
Error: Failed to get existing workspaces: querying Cloud Storage...
```
**Fix:** Run `bootstrap/bootstrap.sh` first. The state bucket must exist before init.

---

### `terraform validate` fails — provider error
```
Error: Unsupported block type "kubernetes_dashboard"
```
**Fix:** This block was removed in Google provider v5. Ensure `cluster.tf` does not contain a `kubernetes_dashboard {}` block inside `addons_config`.

---

### `terraform apply` fails — GKE quota exceeded
```
Error: googleapi: Error 403: Insufficient regional quota...
```
**Fix:** Request quota increase in GCP Console → IAM & Admin → Quotas. Filter by region `asia-south1` and increase `CPUS` and `IN_USE_ADDRESSES`.

---

### ArgoCD shows `OutOfSync` for root application
```bash
# Check what repoURL ArgoCD is using
kubectl get application root -n argocd -o yaml | grep repoURL
```
If it shows `YOUR_USERNAME/project-2` instead of your actual repo — the git_repo_url placeholder was not replaced. Fix in `terraform/environments/dev/main.tf` → `git_repo_url` and re-apply.

---

### ArgoCD cannot clone the repo
```
Failed to fetch: error fetching repository
```
**Fix:** The repository must be **public**, or you must add deploy keys. For this project, the GitHub repo should be public.

---

### OTel Demo pods stuck in `Pending`
```bash
# Check what's blocking the pod
kubectl describe pod <pending-pod-name> -n otel-demo-dev | grep -A5 Events
```
**Common causes:**
- Nodes not yet ready → wait 3–5 minutes
- Not enough CPU/memory → general pool needs to scale up
- PriorityClass not yet created → check `kubectl get priorityclasses`

---

### WIF auth fails in GitHub Actions
```
Error: google-github-actions/auth failed with: the GitHub Actions workflow must specify exactly one of "workload_identity_provider"
```
**Fix:** Verify these in GitHub Actions Variables:
- `GCP_WIF_PROVIDER` must start with `projects/` (not `//iam...`)
- `GCP_SA_EMAIL` must end with `.iam.gserviceaccount.com`
- GitHub repo name in WIF attribute condition must match exactly: `devSatym/gcp-platform-engineering`

---

### `kubectl top nodes` returns no metrics
```
error: Metrics API not available
```
**Fix:** Wait 2–3 minutes for metrics-server to initialize. Check: `kubectl get pods -n kube-system | grep metrics-server`.

---

### Terraform state lock error
```
Error: Error acquiring the state lock
  Lock Info: ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```
**Fix:** Another Terraform process is running (or a previous one crashed). Force-unlock **only if you are sure no other apply is in progress**:
```bash
terraform force-unlock LOCK_ID_FROM_ERROR_MESSAGE
```

---

*Guide covers: Phase 1 (Bootstrap) · Phase 2 (Networking) · Phase 3 (GKE) · Phase 4 (ArgoCD GitOps) · Phase 5 (OTel Demo + Artifact Registry) · Phase 6 (GitHub Actions CI/CD + WIF)*
