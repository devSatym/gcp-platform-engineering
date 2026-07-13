# Module: `github-wif`

> **Path:** `terraform/modules/github-wif/`  
> **Called from:** `environments/dev/main.tf` → `module "github_wif"`  
> **Phase:** 6 (GitHub Actions CI/CD)

---

## Files

| File | Purpose |
|------|---------|
| `main.tf` | WIF pool + provider (via gcloud), IAM binding (via TF) |
| `variables.tf` | `project_id`, `github_repo`, `github_actions_sa_email` |
| `outputs.tf` | WIF provider name, pool name, SA email |
| `versions.tf` | Required providers |

---

## Why This Uses `null_resource` + gcloud Instead of Terraform Resources

This is the most important design decision in this module.

**The Problem:**  
GCP does **NOT hard-delete** WIF pools or providers. When you run `terraform destroy`:
- GCP soft-deletes the pool (enters `DELETED` state for 30 days)
- Next `terraform apply` — Terraform sees no resource in state → calls `CREATE` API
- GCP returns **HTTP 409**: `"Requested entity already exists"`

**The failed previous approach:**
1. `null_resource` undeletes the pool (pool is `ACTIVE` again)
2. `google_iam_workload_identity_pool` resource calls `CREATE` anyway (not in Terraform state)
3. GCP returns 409

**The fix:** Manage pool/provider **entirely via gcloud** scripts. No Terraform resource = no 409 ever.

---

## `main.tf` — Resources

### Data + Locals

```hcl
data "google_project" "project" {
  project_id = var.project_id
}

locals {
  wif_pool_name     = "projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/github-pool"
  wif_provider_name = "${local.wif_pool_name}/providers/github-provider"
}
```

`data.google_project` fetches the **numeric** project number (e.g., `123456789`).  
The WIF resource name requires the numeric project number (not the string project ID).  
Locals compute the full resource names — used in outputs and the IAM binding.

---

### Resource 1: `null_resource "wif_pool"` — Fully Idempotent Pool Management

```hcl
resource "null_resource" "wif_pool" {
  triggers = {
    pool_id    = "github-pool"
    project_id = var.project_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      POOL_STATE=$(gcloud iam workload-identity-pools describe github-pool \
        --location=global --project=${var.project_id} \
        --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

      if   [ "$POOL_STATE" = "ACTIVE"  ]; then echo "Pool ACTIVE — noop."
      elif [ "$POOL_STATE" = "DELETED" ]; then
        gcloud iam workload-identity-pools undelete github-pool \
          --location=global --project=${var.project_id}
        sleep 15
      else
        gcloud iam workload-identity-pools create github-pool \
          --location=global --project=${var.project_id} \
          --display-name="GitHub Actions Pool"
        sleep 10
      fi
    EOT
  }
}
```

**3 states handled:**
| Pool State | Action |
|-----------|--------|
| `ACTIVE` | No-op — already exists and is active |
| `DELETED` | `gcloud ... undelete` — soft-deleted pools can be restored within 30 days |
| `NOT_FOUND` | `gcloud ... create` — first-time creation |

**`sleep` after operations:** Allows GCP control plane to propagate the change before the provider resource runs.

---

### Resource 2: `null_resource "wif_provider"` — Fully Idempotent Provider Management

```hcl
resource "null_resource" "wif_provider" {
  triggers = {
    pool_id     = "github-pool"
    provider_id = "github-provider"
    project_id  = var.project_id
    github_repo = var.github_repo
  }

  provisioner "local-exec" {
    command = <<-EOT
      PROVIDER_STATE=$(gcloud iam workload-identity-pools providers describe github-provider \
        --workload-identity-pool=github-pool \
        --location=global --project=${var.project_id} \
        --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

      if [ "$PROVIDER_STATE" = "ACTIVE" ]; then echo "Provider ACTIVE — noop."
      elif [ "$PROVIDER_STATE" = "DELETED" ]; then
        gcloud iam workload-identity-pools providers undelete github-provider \
          --workload-identity-pool=github-pool --location=global --project=${var.project_id}
        sleep 15
      else
        gcloud iam workload-identity-pools providers create-oidc github-provider \
          --workload-identity-pool=github-pool \
          --location=global --project=${var.project_id} \
          --display-name="GitHub OIDC Provider" \
          --issuer-uri="https://token.actions.githubusercontent.com" \
          --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.workflow=assertion.workflow,attribute.ref=assertion.ref" \
          --attribute-condition="assertion.repository == '${var.github_repo}'"
        sleep 10
      fi
    EOT
  }

  depends_on = [null_resource.wif_pool]
}
```

**Key provider settings:**
- **Issuer URI:** `https://token.actions.githubusercontent.com` — GitHub's OIDC endpoint
- **Attribute mapping:** Maps GitHub JWT claims to GCP identity attributes:
  - `assertion.sub` → `google.subject`
  - `assertion.repository` → `attribute.repository`
  - `assertion.actor` → `attribute.actor`
  - `assertion.ref` → `attribute.ref` (branch/tag)
- **Attribute condition:** `assertion.repository == '{owner}/{repo}'` — **restricts to your specific repo only**. Other GitHub repos cannot authenticate.

---

### Resource 3: `google_service_account_iam_member "github_wif_binding"` — IAM Binding

```hcl
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.github_actions_sa_email}"
  role               = "roles/iam.workloadIdentityUser"

  member = "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repository/${var.github_repo}"

  depends_on = [null_resource.wif_provider]
}
```

**Member format:** `principalSet://iam.googleapis.com/projects/{number}/locations/global/workloadIdentityPools/github-pool/attribute.repository/devSatym/gcp-platform-engineering`

This allows **any GitHub Actions run from `devSatym/gcp-platform-engineering`** to impersonate `sa-github-actions`.

**`depends_on = [null_resource.wif_provider]`** — binding is only created after the provider exists.

---

## Authentication Flow (End to End)

```
GitHub Actions job starts
  │ requests OIDC token
  ▼
GitHub OIDC Provider (token.actions.githubusercontent.com)
  │ issues JWT: {sub, repository, actor, ref, workflow}
  ▼
GCP WIF Pool validates JWT against GitHub's JWKS endpoint
  │ maps JWT claims → GCP identity attributes
  ▼
Attribute condition check: assertion.repository == 'devSatym/gcp-platform-engineering'
  │ passes if running from the correct repo
  ▼
IAM binding: principalSet/attribute.repository → sa-github-actions
  │ short-lived GCP access token issued
  ▼
GCP APIs: Artifact Registry push, GKE get-credentials
```

---

## `variables.tf`

| Variable | Type | Description |
|----------|------|-------------|
| `project_id` | string | GCP project ID |
| `github_repo` | string | `"owner/repo"` format — only this repo can auth |
| `github_actions_sa_email` | string | `sa-github-actions` email from service-accounts module |

---

## `outputs.tf` — What Gets Set as GitHub Actions Secrets

| Output | Value | Set As |
|--------|-------|--------|
| `workload_identity_provider` | `projects/{number}/locations/global/workloadIdentityPools/github-pool/providers/github-provider` | `GCP_WIF_PROVIDER` GitHub Actions variable |
| `workload_identity_pool_name` | `projects/{number}/locations/global/workloadIdentityPools/github-pool` | Informational |
| `github_actions_sa_email` | `sa-github-actions@{project}.iam.gserviceaccount.com` | `GCP_SA_EMAIL` GitHub Actions variable |

These two values are passed to `google-github-actions/auth@v2` in the GitHub Actions workflow:

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
    service_account: ${{ vars.GCP_SA_EMAIL }}
```
