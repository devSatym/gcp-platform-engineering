# GitOps Documentation

This directory covers every file in `gitops/` — how ArgoCD discovers, manages, and reconciles the cluster.

## Files in This Directory

| File | What It Covers |
|------|---------------|
| [01-gitops-overview.md](./01-gitops-overview.md) | App of Apps pattern, sync waves, how ArgoCD works |
| [02-bootstrap-layer.md](./02-bootstrap-layer.md) | `gitops/bootstrap/` — projects, namespaces, ApplicationSets |
| [03-platform-layer.md](./03-platform-layer.md) | `gitops/platform/` — ESO, metrics-server, priority-classes |
| [04-applications-layer.md](./04-applications-layer.md) | `gitops/applications/` — OTel Demo multi-source pattern |

## Directory Structure

```
gitops/
├── bootstrap/                 ← ArgoCD watches this (root app points here)
│   ├── projects.yaml          ← AppProjects: security boundaries
│   ├── namespaces.yaml        ← All platform namespaces
│   ├── platform-appset.yaml   ← ApplicationSet: platform components per env
│   └── applications-appset.yaml  ← ApplicationSet: OTel Demo per env
│
├── platform/                  ← Discovered by platform-appset.yaml
│   ├── external-secrets.yaml  ← ESO Application
│   ├── metrics-server.yaml    ← metrics-server Application
│   └── priority-classes.yaml  ← PriorityClass cluster resources
│
├── applications/              ← Values overlay for OTel Demo chart
│   └── opentelemetry-demo/
│       └── values/
│           ├── base.yaml      ← Common OTel Demo config
│           └── dev.yaml       ← Dev-specific overrides
│
├── environments/              ← Environment-specific overlays (future)
├── networking/                ← Istio/Gateway config (Phase 9)
├── observability/             ← Prometheus/Grafana (Phase 8)
├── security/                  ← Kyverno/Falco (Phase 7)
├── tenants/                   ← Multi-tenant config (future)
└── projects/                  ← Additional projects (future)
```

## Sync Wave Order

```
Wave -3  : root Application (applied by Terraform null_resource)
Wave -2  : namespaces.yaml (all platform namespaces)
Wave -1  : projects.yaml (AppProjects) + platform-appset.yaml + applications-appset.yaml
Wave  0  : platform components (ESO, metrics-server, priority-classes)
Wave  2  : business applications (OTel Demo)
```
