# Module: `artifact-registry`

> **Path:** `terraform/modules/artifact-registry/`  
> **Called from:** `environments/dev/main.tf` → `module "artifact_registry"`  
> **Phase:** 5 (Container Registry)

---

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Docker registry + 2 IAM bindings (GKE reader, GitHub writer) |
| `variables.tf` | `project_id`, `region`, `repository_id`, SA emails, `labels` |
| `outputs.tf` | `registry_url`, `docker_auth_command` |

---

## `main.tf` — Resources

### `google_artifact_registry_repository "docker"`

```hcl
resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region           # "asia-south1" — co-located with GKE cluster
  repository_id = var.repository_id   # default: "platform"
  format        = "DOCKER"

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-last-10-tagged"
    action = "KEEP"
    most_recent_versions { keep_count = 10 }
  }

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition { tag_state = "UNTAGGED" }
  }

  labels = var.labels
}
```

**Lifecycle policies (two rules):**
- **Keep last 10 tagged:** Retains the 10 most recent tagged versions of each image → preserves rollback capability
- **Delete untagged:** Removes any untagged/intermediate layers → prevents unbounded storage growth

**Co-location benefit:** Registry in `asia-south1` same as GKE cluster → zero egress cost, faster image pulls.

---

### `google_artifact_registry_repository_iam_member "gke_node_reader"`

```hcl
resource "google_artifact_registry_repository_iam_member" "gke_node_reader" {
  repository = google_artifact_registry_repository.docker.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.gke_node_sa_email}"  # sa-gke-nodes
}
```

**Grants GKE nodes pull access** at the registry level. This is in addition to the project-level `roles/artifactregistry.reader` granted in the `service-accounts` module (belt-and-suspenders).

---

### `google_artifact_registry_repository_iam_member "github_actions_writer"`

```hcl
resource "google_artifact_registry_repository_iam_member" "github_actions_writer" {
  repository = google_artifact_registry_repository.docker.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.github_actions_sa_email}"  # sa-github-actions
}
```

**Grants GitHub Actions push access** at the registry level. Created in Phase 5 so Phase 6 CI/CD works without additional Terraform runs.

---

## `outputs.tf`

| Output | Value | Used By |
|--------|-------|---------|
| `registry_url` | `asia-south1-docker.pkg.dev/{project}/platform` | `environments/dev/outputs.tf` → printed after apply; used as Docker image prefix in GitHub Actions |
| `repository_id` | `"platform"` | Informational |
| `repository_name` | Full resource name | Informational |
| `docker_auth_command` | `gcloud auth configure-docker asia-south1-docker.pkg.dev` | Run once locally before `docker push` |

---

## Image Strategy by Phase

| Phase | Image Source | Registry Used |
|-------|-------------|---------------|
| Phase 5 | Upstream `ghcr.io/open-telemetry` (OTel Demo Helm chart) | Public (no AR needed) |
| Phase 6 | GitHub Actions builds + pushes to AR | `asia-south1-docker.pkg.dev/{project}/platform` |
| Phase 7 | Images signed via Cosign + Binary Authorization enforces signing | Same AR + KMS signing key |
