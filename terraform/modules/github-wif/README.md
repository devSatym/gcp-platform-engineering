# Module: github-wif

Configures **Workload Identity Federation (WIF)** to allow GitHub Actions to authenticate to GCP without storing JSON service account keys as GitHub secrets.

## Why WIF?

| Approach | Security | Maintenance |
|---|---|---|
| JSON key in GitHub secret | ❌ Long-lived credential, secret sprawl | ❌ Manual rotation |
| WIF (OIDC) | ✅ Short-lived token (1hr), no secret storage | ✅ Zero rotation needed |

JSON keys are a single point of compromise — if a key leaks, anyone can access GCP. WIF issues short-lived tokens that expire after 1 hour and are cryptographically bound to the specific workflow run.

## How It Works

```
GitHub Actions job starts
       │  requests OIDC token (JWT) from GitHub
       ▼
GitHub OIDC  (https://token.actions.githubusercontent.com)
       │  issues JWT: { repository, actor, ref, workflow, ... }
       ▼
GCP WIF Pool  (validates JWT, checks issuer + audience)
       │  attribute condition: assertion.repository == 'owner/repo'
       ▼
sa-github-actions GCP SA  (impersonated — issues short-lived access token)
       │  has roles: AR writer, GKE developer, token creator (Phase 2)
       ▼
GCP APIs  (push to Artifact Registry, get GKE credentials)
```

## Usage

```hcl
module "github_wif" {
  source                  = "../../modules/github-wif"
  project_id              = var.project_id
  github_repo             = "satyam-agnihotri/project-2"  # owner/repo format
  github_actions_sa_email = module.service_accounts.github_actions_sa_email

  depends_on = [module.project]
}
```

## GitHub Actions Usage

In your workflow YAML (after `terraform output wif_provider`):

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: 'projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
    service_account: 'sa-github-actions@PROJECT_ID.iam.gserviceaccount.com'
```

Store these as GitHub Actions variables (not secrets, they're not sensitive):
- `GCP_WIF_PROVIDER` → value of `terraform output wif_provider`
- `GCP_SA_EMAIL` → value of `terraform output github_actions_sa_email`

## Important: github_repo Must Be Updated

```hcl
github_repo = "YOUR_GITHUB_USERNAME/project-2"  # Update before applying
```

The attribute condition restricts WIF to ONLY your repository. Without this, any GitHub user could potentially authenticate to your GCP project.

## Inputs

| Name | Type | Description |
|---|---|---|
| `project_id` | `string` | GCP project ID |
| `github_repo` | `string` | GitHub repo in `owner/repo` format |
| `github_actions_sa_email` | `string` | SA email from service-accounts module |

## Outputs

| Name | Description |
|---|---|
| `workload_identity_provider` | Full provider name for `google-github-actions/auth` |
| `workload_identity_pool_name` | Pool resource name |
| `github_actions_sa_email` | SA being impersonated |
