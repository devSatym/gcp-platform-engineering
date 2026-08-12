# GitOps Overview — App of Apps Pattern

> **How Terraform hands off to ArgoCD, and how ArgoCD takes over.**

---

## The Terraform → GitOps Handoff

```
terraform apply (argocd-bootstrap module)
  │
  ├── helm_release.argocd  ← Installs ArgoCD via Helm (wait=true, pods must be Ready)
  │
  └── null_resource.root_application  ← kubectl apply (runs AFTER helm_release)
        │
        ├── Step 1: kubectl apply gitops/bootstrap/projects.yaml
        │           (AppProjects must exist before Applications reference them)
        │
        └── Step 2: kubectl apply root-application.yaml
                    → ArgoCD Application: { path: gitops/bootstrap, repo: monorepo }
```

After Step 2, **Terraform's job is done forever** for Kubernetes resources.  
ArgoCD watches `gitops/bootstrap/` and reconciles continuously.

---

## App of Apps Pattern

The "App of Apps" (or "root app") pattern works like a tree:

```
root Application
  └─ watches gitops/bootstrap/
       ├── namespaces.yaml           → creates all Namespaces
       ├── projects.yaml             → creates all AppProjects
       ├── platform-appset.yaml      → generates platform-dev Application
       │                                 └─ watches gitops/platform/
       │                                      ├── external-secrets.yaml
       │                                      ├── metrics-server.yaml
       │                                      └── priority-classes.yaml
       └── applications-appset.yaml  → generates otel-demo-dev Application
                                          └─ multi-source: upstream chart + our values
```

**Benefits:**
- **Single source of truth:** Add a new app by pushing a YAML to `gitops/bootstrap/` — ArgoCD auto-discovers it
- **Self-healing:** If someone deletes a namespace manually, ArgoCD recreates it from Git
- **Audit trail:** Every cluster change is a Git commit

---

## Sync Waves

ArgoCD processes resources in ascending sync wave order within an application. Across applications, the root app's sync wave controls order.

| Wave | Resource | Why That Order |
|------|----------|----------------|
| `-3` | `root` Application | Root must exist first (applied by Terraform) |
| `-2` | `namespaces.yaml` | Namespaces must exist before any pod can be created |
| `-1` | `projects.yaml` | `AppProject` must exist before `Application` references it |
| `-1` | `platform-appset.yaml` | AppSet creates Applications, which must exist before sync |
| `-1` | `applications-appset.yaml` | Same |
| `0` | ESO, metrics-server, priority-classes | Operators install before their CRs |
| `2` | OTel Demo | Business app deploys after platform operators are healthy |

**How sync waves are set:**

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

---

## Automated Sync Policy

All ArgoCD Applications in this platform use:

```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources deleted from Git
    selfHeal: true   # Revert manual kubectl changes
  syncOptions:
    - CreateNamespace=true    # ArgoCD creates missing namespaces
    - ServerSideApply=true    # Uses SSA for drift detection (vs client-side apply)
    - RespectIgnoreDifferences=true
```

**`prune: true`** — if you delete a YAML from Git, ArgoCD deletes the resource from the cluster.  
**`selfHeal: true`** — if someone does `kubectl edit` or `kubectl delete`, ArgoCD reverts it from Git.  
**`ServerSideApply`** — required when mixing Helm and ArgoCD management. Prevents field ownership conflicts.

---

## ArgoCD Projects (Security Boundaries)

Each `AppProject` defines:
1. **Which Git paths** can be sourced (prevents arbitrary Helm repo injection)
2. **Which namespaces** resources can be deployed to (blast radius control)
3. **Which cluster-scoped resources** (CRDs, ClusterRoles) are allowed

| Project | Manages | Namespaces |
|---------|---------|------------|
| `platform` | ESO, metrics-server, cert-manager | `platform-system`, `argocd`, `kube-system` |
| `applications` | OTel Demo, business apps | `applications`, `otel-demo-dev/staging/prod` |
| `observability` | Prometheus, Grafana, Loki | `observability` |
| `networking` | Istio, Gateway API | `networking`, `istio-system`, `istio-ingress` |
| `security` | Kyverno, Falco | `security`, `kyverno`, `falco` |
| `default` | root Application | `argocd` |

---

## ApplicationSet vs Application

| Concept | When to Use | In This Project |
|---------|-------------|----------------|
| `Application` | Single environment, manually defined | `external-secrets.yaml`, `metrics-server.yaml` |
| `ApplicationSet` | Generate multiple Applications from a template | `platform-appset.yaml`, `applications-appset.yaml` |

`ApplicationSet` with a `list` generator creates one `Application` per element. When staging/prod clusters are added, just add entries to the generator list — no new YAML files needed.

---

## GitOps vs Terraform: Division of Responsibility

| Concern | Managed By | Where |
|---------|-----------|-------|
| GCP VPC, subnets | Terraform | `terraform/modules/networking/` |
| GKE cluster | Terraform | `terraform/modules/gke/` |
| GCP IAM, service accounts | Terraform | `terraform/modules/service-accounts/` |
| Workload Identity bindings | Terraform | `terraform/modules/argocd-bootstrap/main.tf` |
| GitHub WIF | Terraform | `terraform/modules/github-wif/` |
| ArgoCD install | Terraform (one-time) | `terraform/modules/argocd-bootstrap/main.tf` |
| Kubernetes namespaces | ArgoCD/GitOps | `gitops/bootstrap/namespaces.yaml` |
| Platform operators (ESO, metrics-server) | ArgoCD/GitOps | `gitops/platform/` |
| Business applications (OTel Demo) | ArgoCD/GitOps | `gitops/workloads/` |
| Observability stack (Phase 8) | ArgoCD/GitOps | `gitops/observability/` |
| Security policies (Phase 7) | ArgoCD/GitOps | `gitops/security/` |
