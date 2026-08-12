# Bootstrap Layer — `gitops/bootstrap/`

> **Watched by:** The root ArgoCD Application (created by Terraform `null_resource.root_application`)  
> **Path:** `gitops/bootstrap/`

ArgoCD continuously watches this directory. Every file here is auto-synced to the cluster.

---

## Files

| File | Kind | Sync Wave | Purpose |
|------|------|-----------|---------|
| `projects.yaml` | `AppProject` (×5) | `-1` | Security boundary per application domain |
| `namespaces.yaml` | `Namespace` (×9) | `-2` | All platform namespaces |
| `platform-appset.yaml` | `ApplicationSet` | `-1` | Generates `platform-dev` Application |
| `applications-appset.yaml` | `ApplicationSet` | `+2` | Generates `otel-demo-dev` Application |

---

## `projects.yaml` — AppProjects

### Why AppProjects Exist

Without projects, any ArgoCD Application could deploy to any namespace from any Helm chart repo. AppProjects enforce:
- **Source repos:** Only approved Git repos / Helm chart registries
- **Destination namespaces:** App can't escape its designated namespace
- **Cluster-scoped resources:** CRDs, ClusterRoles are explicitly whitelisted

### Applied FIRST (Chicken-and-Egg Fix)

In `argocd-bootstrap/main.tf` `null_resource.root_application`, `projects.yaml` is applied **before** `root-application.yaml`:

```bash
# STEP 1
kubectl apply --server-side --force-conflicts --validate=false \
  -f "${path.module}/../../../gitops/bootstrap/projects.yaml"
sleep 5

# STEP 2
kubectl apply root-application.yaml
```

**Why:** ArgoCD rejects any `Application` whose `spec.project:` references a non-existent `AppProject`. If the root app is applied first, it tries to create child apps that reference projects not yet created → they fail to sync.

### Projects Defined

#### `platform` AppProject

```yaml
spec:
  description: "Platform system components (ESO, metrics-server, cert-manager)"
  sourceRepos:
    - "https://github.com/devSatym/gcp-platform-engineering.git"
    - "https://charts.external-secrets.io"
    - "https://kubernetes-sigs.github.io/metrics-server"
    - "https://charts.jetstack.io"
  destinations:
    - namespace: platform-system
    - namespace: argocd
    - namespace: kube-system
  clusterResourceWhitelist:
    - ClusterRole, ClusterRoleBinding          # Required by every Helm chart
    - CustomResourceDefinition                  # ESO installs 16 CRDs
    - Namespace                                 # Operators may create namespaces
    - PriorityClass                             # priority-classes.yaml
    - ValidatingWebhookConfiguration            # ESO installs admission webhooks
    - MutatingWebhookConfiguration
    - Application (argoproj.io)                 # gitops/platform/ contains nested Applications
    - APIService (apiregistration.k8s.io)       # metrics-server registers via API aggregation
```

`Application` in clusterResourceWhitelist is critical — `gitops/platform/` contains `Application` manifests (ESO, metrics-server). Without this whitelist entry, ArgoCD cannot create child Applications from the platform project.

#### `applications` AppProject

```yaml
sourceRepos:
  - monorepo
  - "https://open-telemetry.github.io/opentelemetry-helm-charts"
destinations:
  - namespace: applications
  - namespace: otel-demo
  - namespace: otel-demo-dev / otel-demo-staging / otel-demo-prod
clusterResourceWhitelist:
  - ClusterRole, ClusterRoleBinding
  - CustomResourceDefinition     # OTel collector installs CRDs
  - Namespace
  - PriorityClass
```

#### `observability` AppProject

Allows Prometheus/Grafana/Loki Helm repos. Destination: `observability` namespace only.

#### `networking` AppProject

Allows Istio Helm repo. Destinations: `networking`, `istio-system`, `istio-ingress`.

#### `security` AppProject

Allows Kyverno + Falco Helm repos. Destinations: `security`, `kyverno`, `falco`.  
**Extra whitelist:** `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration` — Kyverno installs admission webhooks.

---

## `namespaces.yaml` — All Platform Namespaces

Sync Wave `-2` — processed before any other resource (wave `-1`, `0`, `+2`).

| Namespace | Environment Label | Purpose |
|-----------|------------------|---------|
| `argocd` | `platform` | ArgoCD itself |
| `platform-system` | `platform` | ESO, metrics-server, cert-manager |
| `observability` | `platform` | Prometheus, Grafana, Loki (Phase 8) |
| `security` | `platform` | Kyverno, Falco (Phase 7) |
| `networking` | `platform` | Istio, Gateway config (Phase 9) |
| `applications` | `application` | Generic application namespace |
| `otel-demo-dev` | `dev` | OTel Demo dev environment |
| `otel-demo-staging` | `staging` | OTel Demo staging environment |
| `otel-demo-prod` | `prod` | OTel Demo prod environment |

**Labels on each namespace:**
```yaml
labels:
  app.kubernetes.io/managed-by: argocd
  environment: dev          # varies per namespace
```

Phase 9 will add `istio-injection: enabled` to application namespaces.

**Why manage namespaces in Git:**
- Labels are version-controlled
- ArgoCD recreates accidentally deleted namespaces (selfHeal)
- Istio injection annotations will be set here (Phase 9)

---

## `platform-appset.yaml` — ApplicationSet for Platform Components

### Sync Wave `-1`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-components
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

### Generator

```yaml
generators:
  - list:
      elements:
        - env: dev
          server: https://kubernetes.default.svc
        # staging/prod commented out — single cluster limitation
```

**Single-cluster limitation:** Platform manages cluster-scoped resources (PriorityClasses, ESO CRDs, metrics-server APIService). On a single cluster, only **one** instance can own these. Multiple environments on one cluster cause:
- SSA field manager conflicts on cluster-scoped resources
- Permanent `OutOfSync` on PriorityClasses, ESO, metrics-server

**When to add staging/prod:** Provision separate GKE clusters → add entries with their `server` URLs from ArgoCD cluster secrets.

### Generated Application Template

```yaml
template:
  metadata:
    name: "platform-{{env}}"    # "platform-dev"
  spec:
    project: platform
    source:
      path: gitops/platform    # ← ArgoCD watches gitops/platform/
    destination:
      server: "{{server}}"
      namespace: platform-system
    syncPolicy:
      retry:
        limit: 5
        backoff:
          duration: 5s
          factor: 2
          maxDuration: 3m
```

**`RespectIgnoreDifferences: true`** — required with ServerSideApply when some fields are managed by the K8s controller (not ArgoCD).

---

## `applications-appset.yaml` — ApplicationSet for OTel Demo

### Sync Wave `+2`

```yaml
annotations:
  argocd.argoproj.io/sync-wave: "2"
```

Business apps deploy **after** platform components (ESO, metrics-server, priority-classes) are healthy.

### Generator

```yaml
generators:
  - list:
      elements:
        - env: dev
          server: https://kubernetes.default.svc
          chartVersion: "0.40.9"
```

**Single-cluster OTel limitation:** OTel Demo sub-charts (Grafana, Prometheus, Jaeger) install ClusterRoles with **fixed names** (`grafana-clusterrole`, `prometheus`). Multiple environments on one cluster → naming collisions → `SharedResourceWarning` → apps marked `Degraded`.

### Multi-Source Pattern

```yaml
spec:
  project: applications
  sources:
    # Source 1: Upstream OTel Demo Helm chart
    - repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts
      chart: opentelemetry-demo
      targetRevision: "{{chartVersion}}"
      helm:
        releaseName: otel-demo
        valueFiles:
          - $values/gitops/workloads/opentelemetry-demo/values/base.yaml
          - $values/gitops/workloads/opentelemetry-demo/values/{{env}}.yaml

    # Source 2: Our monorepo (provides the $values reference)
    - repoURL: "https://github.com/devSatym/gcp-platform-engineering.git"
      targetRevision: main
      ref: values    # ← Declares this as the $values reference
```

**Why multi-source?**  
Without multi-source, you'd have to either:
1. **Fork the upstream chart** — painful to keep in sync with upstream releases
2. **Copy the entire chart** into the monorepo — massive, hard to update

Multi-source (ArgoCD 2.6+) lets you use the upstream chart unmodified and overlay only your custom values from the monorepo. `$values` references the second source.

### IgnoreDifferences

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /status
  - group: apps
    kind: StatefulSet
    jsonPointers:
      - /status
  - group: ""
    kind: Service
    jsonPointers:
      - /spec/clusterIPs
```

Prevents `ComparisonError` from K8s API fields not in ArgoCD's schema (e.g., `.status.terminatingReplicas`). `clusterIPs` is assigned by Kubernetes and shouldn't be tracked by ArgoCD.
