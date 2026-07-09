# GitOps — Platform as Code

This directory contains all Kubernetes manifests managed by **ArgoCD**. Every resource defined here is automatically deployed, reconciled, and self-healed by the ArgoCD controller running in the cluster.

> **Principle**: Git is the single source of truth. If it's not in Git, it doesn't belong in the cluster.

---

## Repository Layout

```
gitops/
├── bootstrap/           # ArgoCD root application, namespaces, projects, ApplicationSets
├── platform/            # Platform operators: ESO, metrics-server, cert-manager
├── applications/        # Business workloads: OTel Demo (Phase 5)
├── observability/       # Prometheus, Grafana, Loki, OTel Collector (Phase 8)
├── networking/          # Istio, Gateway API config (Phase 9)
├── security/            # Kyverno, Falco policies (Phase 7)
├── tenants/             # Future: multi-tenant application isolation
└── environments/        # Per-environment value overrides
    ├── dev/
    ├── stage/
    └── prod/
```

---

## Bootstrap Sequence

```
Step 1: Terraform Phase 2 → Networking (VPC, NAT, IAM, service accounts)
Step 2: Terraform Phase 3 → GKE cluster (private, regional, 3 node pools)
Step 3: Terraform Phase 4 → ArgoCD installed via Helm (argocd-bootstrap module)
                         → Root Application applied (gitops/bootstrap/root-application.yaml)
Step 4: ArgoCD auto-syncs → gitops/bootstrap/ discovered
                         → Namespaces created (wave -2)
                         → Projects created   (wave -1)
                         → ApplicationSets create platform-dev/stage/prod (wave -1)
Step 5: platform-dev App  → gitops/platform/ synced
                         → External Secrets Operator deployed (wave 0)
                         → metrics-server deployed            (wave 1)
Step 6: Phase 5 onwards  → OTel Demo, observability, security added via new Applications
```

---

## App of Apps Pattern

```
Root Application  (gitops/bootstrap/)
│
├── namespaces.yaml        → 6 platform namespaces
├── projects.yaml          → 5 ArgoCD projects
└── platform-appset.yaml   → ApplicationSet → generates:
    ├── platform-dev       → gitops/platform/
    ├── platform-stage     → gitops/platform/
    └── platform-prod      → gitops/platform/
```

The root application is the **only manually bootstrapped resource** (applied by Terraform). Everything else is discovered and managed automatically.

---

## Sync Wave Strategy

| Wave | Resources | When |
|---|---|---|
| `-3` | Root Application | First — bootstraps everything else |
| `-2` | Namespaces | Before any other resource |
| `-1` | ArgoCD Projects, ApplicationSets | Before Applications reference them |
| `0` | Operators (ESO, cert-manager, Kyverno) | CRDs must exist before their CRs |
| `1` | Controllers (metrics-server) | After operators |
| `2` | Business Applications (OTel Demo) | Last — all platform deps must be ready |

---

## Auto-Sync, Self-Heal, and Prune

All Applications are configured with:

```yaml
syncPolicy:
  automated:
    prune: true     # Remove resources deleted from Git
    selfHeal: true  # Revert manual kubectl changes
```

### Drift Demo

```bash
# Delete a namespace — ArgoCD should recreate it within ~30 seconds
kubectl delete ns platform-system

# Watch ArgoCD reconcile
kubectl get ns -w
# platform-system will reappear automatically
```

---

## Adding a New Platform Component

1. Create `gitops/platform/my-new-tool.yaml` (ArgoCD Application manifest)
2. Set appropriate `sync-wave` annotation
3. Commit and push to `main`
4. ArgoCD auto-syncs within ~3 minutes (or click **Sync** in the UI)

---

## Accessing ArgoCD UI

```bash
# Get credentials
gcloud container clusters get-credentials otel-dev-gke --region=asia-south1

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Open https://localhost:8080 — login: admin / <password above>
```

Phase 9 will expose ArgoCD via GKE Gateway with TLS.

---

## Disaster Recovery

If ArgoCD itself is lost (e.g., cluster recreation):

```bash
# 1. Re-run Terraform Phase 4
cd terraform/environments/dev
terraform apply -target=module.argocd_bootstrap

# 2. ArgoCD reinstalls from Helm chart
# 3. Root Application is reapplied
# 4. ArgoCD auto-discovers and re-syncs all Applications from Git
# Recovery complete — no manual intervention required
```

---

## Important: Update Before Applying

Before running `terraform apply`, update the following placeholders:

| File | Placeholder | Replace With |
|---|---|---|
| `gitops/bootstrap/projects.yaml` | `YOUR_USERNAME` | Your GitHub username |
| `gitops/bootstrap/platform-appset.yaml` | `YOUR_USERNAME` | Your GitHub username |
| `gitops/platform/external-secrets.yaml` | `YOUR_PROJECT_ID` | Your GCP project ID |
| `terraform/environments/dev/main.tf` | `YOUR_USERNAME` | Your GitHub username |
| `terraform/modules/argocd-bootstrap/values.yaml` | (rendered via templatefile) | Handled automatically |
