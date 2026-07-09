# Code Quality & Bug Report — Phases 1-6

> Full deep scan of all Terraform modules, GitHub Actions workflows, GitOps manifests, and shell scripts.
> Issues are classified by severity: **❌ Critical** (will cause apply/runtime failure), **⚠️ Bug** (incorrect behaviour), **🔶 Config Gap** (incomplete/inconsistent), **📝 Cosmetic** (wrong comments, style).

---

## Summary Table

| # | File(s) | Issue | Severity |
|---|---|---|---|
| 1 | `gke/workload_identity.tf` + `argocd-bootstrap/main.tf` | **Duplicate Workload Identity IAM bindings** | ❌ Critical |
| 2 | `environments/*/versions.tf` | **Helm + Kubernetes providers not declared** | ❌ Critical |
| 3 | `security.yaml` | **`subject-digest` fed an image tag, not a digest** | ❌ Critical |
| 4 | `environments/stage/*.tf` + `environments/prod/*.tf` | **Missing `firewall internal_cidr`, networking CIDRs, `spot_pool_machine_type`** | ⚠️ Bug |
| 5 | `terraform.yaml` | **`terraform plan` runs twice — double GCP API cost + state lock risk** | ⚠️ Bug |
| 6 | `release.yaml` | **`run_id` only exists on `workflow_run` trigger — null on manual dispatch** | ⚠️ Bug |
| 7 | `security.yaml` | **Trivy install script fetched from `main` branch (not pinned)** | ⚠️ Bug |
| 8 | `argocd-bootstrap/values.yaml` | **ArgoCD SA Workload Identity annotation points to `argocd_sa_email` for repo-server** | ⚠️ Bug |
| 9 | `gke/cluster.tf` | **`node_config` block on cluster-level (used only for default pool which is removed)** | 🔶 Config Gap |
| 10 | `gke/cluster.tf` | **Maintenance window `start_time`/`end_time` hardcoded to 2026** | 🔶 Config Gap |
| 11 | `argocd-bootstrap/root-application.yaml` | **Root Application uses `project: default` instead of `project: platform`** | 🔶 Config Gap |
| 12 | `argocd-bootstrap/variables.tf` | **Default `git_repo_url` still contains `YOUR_USERNAME` placeholder** | 🔶 Config Gap |
| 13 | `environments/stage/versions.tf` + `environments/prod/versions.tf` | **Header comment says `environments/dev/versions.tf`** | 📝 Cosmetic |
| 14 | `environments/stage/locals.tf` + `environments/prod/locals.tf` | **Header comment says `environments/dev/locals.tf`** | 📝 Cosmetic |
| 15 | `environments/stage/outputs.tf` | **Header comment still says `environments/dev/outputs.tf`** | 📝 Cosmetic |
| 16 | `platform-appset.yaml` | **All 3 environment apps deploy to the same `platform-system` namespace** | 📝 Cosmetic |
| 17 | `ci.yaml` | **`tflint --init` runs per module with internet access needed in CI** | 📝 Cosmetic |

---

## ❌ Critical Issues

---

### Issue 1 — Duplicate Workload Identity IAM Bindings

**Files:**
- `terraform/modules/gke/workload_identity.tf`
- `terraform/modules/argocd-bootstrap/main.tf`

**Problem:**
Identical `google_service_account_iam_member` resources exist in **both** modules, creating the **same 3 IAM bindings twice**:
- `argocd/argocd-server` → `sa-argocd`
- `argocd/argocd-repo-server` → `sa-argocd`
- `platform-system/external-secrets` → `sa-external-secrets`

When `terraform apply` runs, Terraform will attempt to create the same IAM binding in two separate modules. The second creation **will fail** with a conflict error (IAM bindings are idempotent at the GCP level, so GCP may silently succeed, but Terraform will see conflicting state and resource drift).

**Root Cause:**
The WI bindings were initially scaffolded in `gke/workload_identity.tf`. When the `argocd-bootstrap` module was built, the same bindings were added again without removing the originals.

**Fix:**
Remove all 3 `google_service_account_iam_member` resources from `terraform/modules/gke/workload_identity.tf`. Keep them **only** in `terraform/modules/argocd-bootstrap/main.tf` since that module has the `argocd_sa_email` and `external_secrets_sa_email` variables directly.

Alternatively, remove them from `argocd-bootstrap/main.tf` and keep them in `gke/workload_identity.tf` since both SA emails are passed as variables there. Either approach works — the key is to remove one set entirely.

---

### Issue 2 — Helm & Kubernetes Providers Not Declared in Environment `versions.tf`

**Files:**
- `terraform/environments/dev/versions.tf`
- `terraform/environments/stage/versions.tf`
- `terraform/environments/prod/versions.tf`

**Problem:**
Each environment's `versions.tf` only declares `google` and `google-beta` providers. However, the `argocd-bootstrap` module (called from each environment's `main.tf`) uses `helm` and `kubernetes` providers, declared in its own `providers.tf`.

In Terraform, **provider declarations in child modules are deprecated and ignored for provider configuration**. The parent (environment root) must declare all providers required by its child modules. Without declaring `helm` and `kubernetes` at the root level, `terraform init` will fail because Terraform cannot locate the provider source for the module.

**Error you will see:**
```
Error: Failed to query available provider packages
  Could not retrieve the list of available versions for provider hashicorp/helm
```

**Fix:**
Add the following to each environment's `versions.tf` inside `required_providers`:
```hcl
helm = {
  source  = "hashicorp/helm"
  version = "~> 2.12"
}
kubernetes = {
  source  = "hashicorp/kubernetes"
  version = "~> 2.27"
}
```

---

### Issue 3 — `subject-digest` in SLSA Provenance Is an Image Tag, Not a Digest

**File:** `.github/workflows/security.yaml` (line 178)

**Problem:**
```yaml
- name: Generate SLSA provenance attestation
  uses: actions/attest-build-provenance@v1
  with:
    subject-name: ${{ env.REGISTRY }}/.../otel-collector-custom
    subject-digest: ${{ steps.image.outputs.image }}   # ← BUG: this is a full image:tag string
```

The `subject-digest` parameter **must be a digest in `sha256:abc...` format** (e.g., `sha256:abc123def456`). Instead, `steps.image.outputs.image` is set to the full image reference string (e.g., `asia-south1-docker.pkg.dev/project/repo/service:sha-abc1234`), which is not a digest.

**Impact:** The SLSA provenance attestation step will fail at runtime with:
```
Error: invalid subject digest "asia-south1-docker.pkg.dev/...image:sha-abc1234"
```

**Fix:**
Use the `digest` output instead, and use `subject-name` for the image reference. The `digest` output (set 3 lines above using `docker buildx imagetools inspect`) is the correct input:
```yaml
subject-name: ${{ env.REGISTRY }}/${{ env.GCP_PROJECT_ID }}/platform-docker/otel-collector-custom
subject-digest: ${{ steps.image.outputs.digest }}   # ← correct: sha256:...
```

---

## ⚠️ Bugs

---

### Issue 4 — Stage/Prod `main.tf` Missing Config Passed to Modules

**Files:**
- `terraform/environments/stage/main.tf`
- `terraform/environments/prod/main.tf`

**Sub-issues:**

**4a — Firewall module missing `internal_cidr` argument:**
Dev passes `internal_cidr = "10.0.0.0/16"` to the firewall module. Stage and prod don't pass it at all. The module variable likely has a default, but the default may not match the actual VPC CIDR used in stage/prod if those ever get separate IP plans.

**4b — Networking module missing explicit CIDR overrides:**
Dev explicitly sets `gke_subnet_cidr`, `management_subnet_cidr`, `proxy_subnet_cidr`, `gke_pods_cidr`, `gke_services_cidr`. Stage and prod rely on module defaults. This means if the CIDRs need to differ across environments (they should for multi-cluster setups), there's no way to override them without touching the module.

**4c — `spot_pool_machine_type` not set in stage/prod:**
Dev explicitly sets `spot_pool_machine_type = "e2-standard-2"`. Stage and prod rely on the module default. If the default ever changes, stage/prod will silently pick up the new machine type.

**Fix:**
Add the following to `stage/main.tf` and `prod/main.tf`:
```hcl
# In module "networking"
gke_subnet_cidr        = "10.0.0.0/20"
management_subnet_cidr = "10.0.16.0/24"
proxy_subnet_cidr      = "10.0.17.0/24"
gke_pods_cidr          = "10.10.0.0/16"
gke_services_cidr      = "10.20.0.0/20"

# In module "firewall"
internal_cidr = "10.0.0.0/16"

# In module "gke"
spot_pool_machine_type = "e2-standard-2"
```

---

### Issue 5 — `terraform plan` Runs Twice in `terraform.yaml`

**File:** `.github/workflows/terraform.yaml` (lines 166-175)

**Problem:**
The plan job runs `terraform plan` twice in sequence:
1. Line 166: `terraform plan -out=plan.tfplan 2>&1 | tee plan-output.txt` — saves the plan file
2. Line 173: `terraform plan -input=false -no-color -detailed-exitcode` — runs the plan again just to capture the exit code

**Impact:**
- Double the GCP API calls (each plan calls dozens of `Get` APIs)
- Double the time spent planning (~2-5 extra minutes per run)
- Risk of state lock conflict if a concurrent apply is in progress
- The second plan may diverge from the first if infrastructure changes between the two runs (race condition)

**Fix:**
Capture the exit code from the first `terraform plan` using `|| true` and inspect it:
```bash
terraform plan \
  -input=false \
  -no-color \
  -detailed-exitcode \
  -out=plan.tfplan \
  2>&1 | tee plan-output.txt
PLAN_EXIT=${PIPESTATUS[0]}
echo "plan_exit_code=${PLAN_EXIT}" >> $GITHUB_OUTPUT
```

---

### Issue 6 — `release.yaml` Uses `workflow_run.id` Which is Null on Manual Dispatch

**File:** `.github/workflows/release.yaml` (line 84)

**Problem:**
```yaml
- uses: dawidd6/action-download-artifact@v6
  with:
    run_id: ${{ github.event.workflow_run.id }}   # ← null when triggered by tag push
```

The `release.yaml` workflow is triggered by a `push` to a version tag (not by `workflow_run`). In this context, `github.event.workflow_run` is `null` — there is no triggering workflow run. The `run_id` will be an empty string, causing the artifact download action to fail trying to find an artifact with no run ID.

**Impact:** The SBOM download step will fail, but since `continue-on-error: true` is set, it will silently fail and the release will be created without an SBOM attached.

**Fix:**
Either:
- Remove the `run_id` field (let it use the latest run from `security.yaml`) and add `workflow_run_id: ${{ github.run_id }}` as a search constraint
- Or add an explicit lookup for the last security workflow run ID using the GitHub API:
```bash
SECURITY_RUN_ID=$(gh api repos/${{ github.repository }}/actions/workflows/security.yaml/runs \
  --jq '.workflow_runs[0].id')
```

---

### Issue 7 — Trivy Install Script Fetched from Unstable `main` Branch

**File:** `.github/workflows/security.yaml` (line 100)

**Problem:**
```bash
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /usr/local/bin v0.50.1
```

The install script itself is fetched from `aquasecurity/trivy`'s **`main` branch** (not pinned to any commit or tag). If the install script changes on the main branch (e.g., changes to environment variables, argument parsing, or binary paths), the CI job will break silently on the next run. This is a supply chain risk.

**Fix:**
Use the official `aquasecurity/trivy-action@0.24.0` GitHub Action instead, which is version-pinned and maintained:
```yaml
- name: Trivy scan
  uses: aquasecurity/trivy-action@0.24.0
  with:
    image-ref: ${{ steps.image.outputs.image }}
    format: sarif
    output: trivy-results.sarif
    severity: CRITICAL,HIGH,MEDIUM
    exit-code: '1'
    severity: CRITICAL
```

---

### Issue 8 — ArgoCD `repo-server` WI Annotation Points to Wrong SA

**File:** `terraform/modules/argocd-bootstrap/values.yaml`

**Problem:**
```yaml
repoServer:
  serviceAccount:
    annotations:
      iam.gke.io/gcp-service-account: "${argocd_sa_email}"
```

The `repo-server` component of ArgoCD primarily handles git repository cloning and Helm template rendering. It does **not** need access to GCP Secret Manager. Annotating it with `argocd_sa_email` gives it Secret Manager access unnecessarily, violating the principle of least privilege.

**Impact:** Not a runtime failure, but a security concern — the repo-server can assume a GCP SA that grants Secret Manager access when it shouldn't need it.

**Fix:**
Remove the `serviceAccount.annotations` from `repoServer` in `values.yaml`. Only the `server` component needs the WI annotation for Secret Manager access.

---

## 🔶 Configuration Gaps

---

### Issue 9 — `node_config` Block on Cluster-Level is Redundant

**File:** `terraform/modules/gke/cluster.tf` (lines 85-95)

**Problem:**
```hcl
node_config {
  machine_type = "e2-medium"
  service_account = var.gke_node_sa_email
  workload_metadata_config { mode = "GKE_METADATA" }
}
```

This `node_config` block configures the **default node pool**, which is immediately removed via `remove_default_node_pool = true`. The config is applied only to create the initial bootstrap node then immediately discarded. The actual node configuration lives in `nodepools.tf`.

This clutters the cluster resource and could cause confusion about what node types are actually running.

**Fix:**
The block is required by GKE to create the cluster (you can't remove the default pool without first creating it). It can stay, but should be explicitly commented to prevent confusion:
```hcl
# This node_config only applies to the temporary default node pool.
# The default pool is deleted immediately (remove_default_node_pool = true).
# All actual node config is in nodepools.tf.
node_config { ... }
```

---

### Issue 10 — Maintenance Window Hardcoded to `2026-01-01`

**File:** `terraform/modules/gke/cluster.tf` (lines 158-159)

**Problem:**
```hcl
start_time = "2026-01-01T20:30:00Z"
end_time   = "2026-01-02T00:30:00Z"
```

The RFC 3339 start/end times in a `recurring_window` are supposed to be anchor dates — GKE uses only the **time portion** and the recurrence rule to determine when maintenance occurs. However, hardcoding a past date is bad practice and will trigger validation warnings in future Terraform provider versions.

**Fix:**
Use a date far enough in the future to avoid any validation issues. Since GKE only uses the time component for recurring windows, a distant future date is cleaner:
```hcl
start_time = "2099-01-01T20:30:00Z"
end_time   = "2099-01-02T00:30:00Z"
```

---

### Issue 11 — Root Application Uses `project: default` Instead of `project: platform`

**File:** `terraform/modules/argocd-bootstrap/root-application.yaml`

**Problem:**
```yaml
spec:
  project: default
```

The root Application is set to use the `default` ArgoCD project. However, this project is not configured with any source repo restrictions, destination restrictions, or cluster resource allowlists. The `platform` ArgoCD project (defined in `gitops/bootstrap/projects.yaml`) has the correct `sourceRepos`, `destinations`, and `clusterResourceWhitelist` configured.

**Impact:** The root Application operates outside all project governance controls. It bypasses the `platform` project's destination and resource-type restrictions.

**Fix:**
```yaml
spec:
  project: platform
```

---

### Issue 12 — `argocd-bootstrap` Module Default `git_repo_url` Contains Placeholder

**File:** `terraform/modules/argocd-bootstrap/variables.tf` (line 58)

**Problem:**
```hcl
variable "git_repo_url" {
  default = "https://github.com/YOUR_USERNAME/project-2.git"
}
```

A placeholder default exists. If a caller ever forgets to pass `git_repo_url` explicitly, `terraform plan` will use this placeholder and ArgoCD will point to a non-existent repository. The root Application creation will succeed (Terraform just applies a YAML manifest) but ArgoCD will immediately fail to clone the repo and show an error.

**Fix:**
Remove the default entirely to force callers to always provide an explicit value:
```hcl
variable "git_repo_url" {
  description = "HTTPS URL of the GitOps monorepo. Example: https://github.com/owner/repo.git"
  type        = string
  # No default — must be set explicitly in each environment's main.tf
}
```

---

## 📝 Cosmetic Issues

---

### Issue 13 — Wrong Filename in Header Comments for Stage/Prod `versions.tf`

**Files:**
- `terraform/environments/stage/versions.tf` — Header says `environments/dev/versions.tf`
- `terraform/environments/prod/versions.tf` — Header says `environments/dev/versions.tf`

**Fix:** Update the header comment to match the actual file path.

---

### Issue 14 — Wrong Filename in Header Comments for Stage/Prod `locals.tf`

**Files:**
- `terraform/environments/stage/locals.tf` — Header says `environments/dev/locals.tf`
- `terraform/environments/prod/locals.tf` — Header says `environments/dev/locals.tf`

**Fix:** Update the header comments to match the actual file paths.

---

### Issue 15 — Wrong Filename in Header Comment for Stage/Prod `outputs.tf`

**Files:**
- `terraform/environments/stage/outputs.tf` — Header says `environments/dev/outputs.tf`
- `terraform/environments/prod/outputs.tf` — Header says `environments/dev/outputs.tf`

**Fix:** Update the header comments to match the actual file paths.

---

### Issue 16 — `platform-appset.yaml` Deploys All 3 Environments to Same Namespace

**File:** `gitops/bootstrap/platform-appset.yaml` (line 52)

**Problem:**
```yaml
destination:
  namespace: platform-system   # Same for dev, stage, and prod
```

All three generated Applications (platform-dev, platform-stage, platform-prod) point to the same single-cluster deployment target (`platform-system`). Since this is a single-cluster setup (one cluster per environment, not one cluster hosting all environments), this is correct behavior — but it could be misleading because the ApplicationSet generates 3 applications that all apply the same configs to the same namespace.

**Note:** This is not actually a bug for the current architecture (one cluster per environment), but it would become a bug if all environments were ever co-located on a single cluster. Worth adding a comment to make the intent clear.

---

### Issue 17 — `tflint --init` in CI Has Implicit Internet Dependency

**File:** `.github/workflows/ci.yaml` (line 110)

**Problem:**
```bash
tflint --init
tflint
```

`tflint --init` downloads TFLint plugins from the internet during the CI job. If the network is slow, the GitHub Actions runner has egress restrictions, or the TFLint plugin registry is down, this step will fail and block all PRs. The plugin versions are also not pinned anywhere, so the exact TFLint rules applied may change silently between runs.

**Fix:**
Create a `.tflint.hcl` config file at the repo root to pin plugin versions:
```hcl
plugin "google" {
  enabled = true
  version = "0.28.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
```

---

## Priority Fix Order

| Priority | Issues | Reason |
|---|---|---|
| **P0 — Fix before any `terraform apply`** | #1, #2 | Will cause apply failure or state corruption |
| **P1 — Fix before CI runs** | #3, #5, #6, #7 | Will cause workflow failures on first run |
| **P2 — Fix for correctness** | #4, #8, #11, #12 | Incorrect behaviour, security concern, or broken feature |
| **P3 — Fix when convenient** | #9, #10, #17 | Non-blocking improvements |
| **P4 — Housekeeping** | #13, #14, #15, #16 | Copy-paste artefacts from dev → stage/prod |
