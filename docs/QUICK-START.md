# Platform Quick Start Guide (Phases 1-6)

This document explains exactly what gets built and the step-by-step process to deploy the entire platform from scratch as it exists right now.

---

## Part 1: What Gets Created and Deployed?

When you run this project, you are building an enterprise-grade GitOps platform on Google Cloud. It is split into two halves: Infrastructure (GCP) and Workloads (Kubernetes).

### 1. Infrastructure (Created by Terraform)
Running Terraform will provision the foundational GCP resources:
* **Networking:** A custom VPC, 3 Subnets (GKE nodes, management, proxy), Cloud Router, and Cloud NAT (for private outbound internet).
* **Security:** 5 Firewall rules and 5 dedicated Service Accounts with least-privilege IAM roles.
* **Kubernetes (GKE):** A private regional GKE cluster with 3 node pools (system, general, spot) and Workload Identity enabled.
* **Registries:** An Artifact Registry (`platform-docker`) for storing container images.
* **CI/CD Auth:** A Workload Identity Federation (WIF) Pool and OIDC Provider, allowing GitHub Actions to securely deploy without using JSON keys.

### 2. Workloads (Deployed automatically by ArgoCD)
Once the infrastructure is up, ArgoCD takes over and automatically syncs the following into your GKE cluster from the `gitops/` folder:
* **Platform Components:** 
  * External Secrets Operator (reads from GCP Secret Manager).
  * Metrics Server (enables Horizontal Pod Autoscaling).
  * PriorityClasses (ensures critical pods schedule first).
* **The Application (OpenTelemetry Demo):**
  * ~20 microservices (Frontend, Checkout, Payment, Recommendation, etc.) deployed into the `otel-demo-dev` namespace.
  * Observability tools: Jaeger (tracing), Prometheus (metrics), and Grafana (dashboards).

### 3. CI/CD Pipelines (GitHub Actions)
The repository is wired with 5 workflows:
* **CI:** Lints code, Helm charts, and Terraform on every PR.
* **Build:** Builds multi-arch Docker images, pushes them to Artifact Registry, and auto-updates GitOps manifests on merges to `main`.
* **Security:** Generates SBOMs, runs Trivy vulnerability scans, and keyless signs images with Cosign.

---

## Part 2: How to Run It Right Now

To bring the entire platform to life, follow these steps in order.

### Step 1: Replace the Placeholders
Before doing anything, you must tell the code your actual GCP Project ID and GitHub Username. Run this single command in your terminal (replace the values in the first two lines):

```bash
GITHUB_USERNAME="your-github-username"
GCP_PROJECT_ID="your-actual-project-id"

# This replaces YOUR_USERNAME, YOUR_PROJECT_ID, etc. across the codebase
find . -type f \( -name "*.tf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.sh" \) \
  ! -path './.git/*' ! -path './.gemini/*' ! -path './docs/*' \
  -exec sed -i "s|YOUR_USERNAME|${GITHUB_USERNAME}|g; s|YOUR_PROJECT_ID|${GCP_PROJECT_ID}|g; s|YOUR_GITHUB_USERNAME|${GITHUB_USERNAME}|g; s|platform-engineering-demo|${GCP_PROJECT_ID}|g" {} +
```

### Step 2: Run the GCP Bootstrap
This one-time script enables necessary GCP APIs and creates the Terraform state bucket.
Ensure you are logged into gcloud (`gcloud auth login`).

```bash
chmod +x bootstrap/bootstrap.sh
./bootstrap/bootstrap.sh
```

### Step 3: Authenticate Terraform
Tell Terraform to use the Service Account created in Step 2.

```bash
gcloud iam service-accounts keys create /tmp/sa-terraform-key.json \
  --iam-account=sa-terraform@${GCP_PROJECT_ID}.iam.gserviceaccount.com
export GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa-terraform-key.json
```

### Step 4: Deploy the Infrastructure (Terraform)
We will deploy the `dev` environment. This provisions the VPC, GKE cluster, Artifact Registry, and installs ArgoCD.

```bash
cd terraform/environments/dev
terraform init
terraform apply
```
*(Type `yes` when prompted. This will take ~15-20 minutes, mostly waiting for the GKE cluster to spin up).*

### Step 5: Verify the Deployment
When Terraform finishes, it prints out several useful commands. Use them to connect to your new cluster:

```bash
# 1. Connect kubectl to your new GKE cluster (copy the exact command from terraform output)
gcloud container clusters get-credentials otel-dev-gke --region asia-south1 --project YOUR_PROJECT_ID

# 2. Watch ArgoCD deploy your platform and the OTel demo
kubectl get pods -A -w

# 3. Access the ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# (Get the admin password using the command from terraform output)

# 4. Access the Application (Astronomy Shop) once pods in `otel-demo-dev` are running
kubectl port-forward svc/otel-demo-frontendproxy -n otel-demo-dev 8080:8080
```

### Step 6: Activate the CI/CD Pipelines
To make the GitHub Actions workflows function, you need to add three variables to your GitHub Repository Settings (**Settings > Secrets and variables > Actions > Variables**):
1. `GCP_PROJECT_ID` - Your GCP project ID.
2. `GCP_WIF_PROVIDER` - Get this from the Terraform output `wif_provider`.
3. `GCP_SA_EMAIL` - Get this from the Terraform output `github_actions_sa_email_wif`.

Once these are set, commit and push your code to GitHub. The pipelines will automatically handle building, scanning, signing, and deploying any future changes you make!
