# Platform GitOps Manifests

Platform-level Kubernetes components managed by ArgoCD. These are the foundation components that all business applications (Phase 5+) depend on.

## Components

| Component | File | Sync Wave | Purpose |
|---|---|---|---|
| External Secrets Operator | `external-secrets.yaml` | 0 | Syncs GCP Secret Manager → K8s Secrets |
| Metrics Server | `metrics-server.yaml` | 1 | HPA/VPA metric aggregation |

## Planned Components (future phases)

| Component | Phase | Purpose |
|---|---|---|
| cert-manager | 9 | TLS certificate management |
| Argo Rollouts | 10 | Progressive delivery (canary, blue/green) |
| Kyverno | 7 | Policy enforcement and admission control |
| OpenTelemetry Operator | 8 | OTel Collector + instrumentation injection |

## How These Are Deployed

These files are discovered by the `platform-appset.yaml` ApplicationSet in `gitops/bootstrap/`. The ApplicationSet generates one ArgoCD Application per environment (`platform-dev`, `platform-stage`, `platform-prod`) all pointing to this directory.

Adding a new platform component is as simple as:
1. Create `gitops/platform/new-component.yaml`
2. Git commit and push
3. ArgoCD auto-syncs and deploys it to all environments

## Workload Identity Flow (External Secrets)

```
ESO Pod
  │  (uses projected K8s SA token from pod volume)
  ▼
GKE Metadata Server
  │  (exchanges token with GCP IAM)
  ▼
GCP IAM  (validates binding: k8s-sa → sa-external-secrets@project.iam.gserviceaccount.com)
  │
  ▼
GCP Secret Manager  (secretAccessor + viewer roles)
  │
  ▼
K8s Secret (synced into platform-system namespace)
```

## Updating a Component Version

```bash
# Edit the targetRevision in the Application YAML
vim gitops/platform/external-secrets.yaml  # Update targetRevision

# Commit and push
git add gitops/platform/external-secrets.yaml
git commit -m "chore: bump external-secrets to 0.13.0"
git push

# ArgoCD auto-syncs within ~3 minutes (or click Sync in UI)
```
