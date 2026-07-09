# Module: artifact-registry

Creates a Docker Artifact Registry repository co-located with the GKE cluster for fast, private container image hosting.

## Why Artifact Registry?

| Concern | Docker Hub / ghcr.io | Artifact Registry |
|---|---|---|
| Location | Global (CDN) | `asia-south1` — same region as GKE |
| Egress cost | Paid for pulls across regions | Free within same region |
| Pull speed | Variable | Fastest possible |
| Privacy | Public or paid private | Always private |
| Vulnerability scanning | Third-party | Built-in (GCP Container Analysis) |
| Binary Authorization | Manual integration | Native integration |
| IAM access | Token-based | GCP IAM (least privilege) |

## Image Strategy

```
Phase 5  →  GKE pulls from upstream public registries (ghcr.io/open-telemetry)
            Registry created and ready — no images yet

Phase 6  →  GitHub Actions mirrors images to this registry using Git SHA tags
            sa-github-actions SA writes images
            sa-gke-nodes SA reads images

Phase 7  →  Images signed by Cosign
            Binary Authorization enforces signed images only
```

## Usage

```hcl
module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id              = var.project_id
  region                  = var.region
  gke_node_sa_email       = module.service_accounts.gke_node_sa_email
  github_actions_sa_email = module.service_accounts.github_actions_sa_email
  labels                  = local.labels
}
```

## Image Naming Convention

```
asia-south1-docker.pkg.dev/{PROJECT_ID}/platform-docker/{service}:{tag}

Examples:
  asia-south1-docker.pkg.dev/my-project/platform-docker/frontend:sha-a83f92d
  asia-south1-docker.pkg.dev/my-project/platform-docker/checkout:1.2.3
  asia-south1-docker.pkg.dev/my-project/platform-docker/custom-collector:sha-b94e01f
```

## Authenticate Docker

```bash
# One-time auth setup for pushing images
gcloud auth configure-docker asia-south1-docker.pkg.dev

# Build and push an image
docker build -t asia-south1-docker.pkg.dev/PROJECT_ID/platform-docker/frontend:sha-$(git rev-parse --short HEAD) .
docker push asia-south1-docker.pkg.dev/PROJECT_ID/platform-docker/frontend:sha-$(git rev-parse --short HEAD)
```

## Lifecycle Policy

- **Keep last 10 tagged versions** — preserves recent rollback capability
- **Delete untagged images** — removes intermediate build artifacts
- Prevents unbounded storage growth while maintaining release history

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | required | GCP project ID |
| `region` | `string` | `asia-south1` | Registry region |
| `repository_id` | `string` | `platform-docker` | Repository name |
| `gke_node_sa_email` | `string` | required | GKE node SA for pull access |
| `github_actions_sa_email` | `string` | required | GitHub Actions SA for push access |
| `labels` | `map(string)` | `{}` | Resource labels |

## Outputs

| Name | Description |
|---|---|
| `registry_url` | Base URL for image tags |
| `repository_id` | Repository name |
| `docker_auth_command` | Command to configure Docker auth |
