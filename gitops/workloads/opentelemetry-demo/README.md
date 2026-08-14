# OpenTelemetry Demo — Platform Engineering Deployment

This directory contains the environment overlays for the upstream [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) (Astronomy Shop) Helm chart.

## Philosophy: Overlay, Don't Fork

```
Upstream chart (open-telemetry/opentelemetry-demo)
         │
         │  (installed as-is)
         ▼
Our values overlay (this directory)
         │
         │  (customizes behavior per environment)
         ▼
Production-grade deployment
```

We never modify the upstream chart. All customizations are additive values overlays. This makes upstream upgrades as simple as bumping `targetRevision` in the ArgoCD ApplicationSet.

---

## Directory Structure

```
opentelemetry-demo/
└── values/
    ├── base.yaml   # Common overrides (all environments)
    ├── dev.yaml    # Dev: 1 replica, load-gen on, debug features
    ├── staging.yaml  # Stage: 2 replicas, PDBs, load test config
    └── prod.yaml   # Prod: 3 replicas, zone spread, PDBs, load-gen off
```

## Service Tier Classification

| Tier | Services | Pool | PriorityClass | PDB |
|---|---|---|---|---|
| **T1 Critical** | Frontend, FrontendProxy, Cart, Checkout, Payment, ProductCatalog | general | `business-critical (900)` | ✅ |
| **T2 Standard** | Email, Recommendation, Currency, Shipping, Ad, Accounting, FraudDetection, Quote | general | `business-standard (500)` | ❌ |
| **T3 Platform** | Shared OTel Collector, Prometheus, Grafana, Tempo, Loki, Flagd | general/system | `platform-critical (1000)` | ✅ (collector) |
| **T4 Non-crit** | Load Generator | spot; general in dev when spot is unavailable | `non-critical (100)` | ❌ |
| **Data** | Valkey, PostgreSQL, Kafka | general | `business-critical (900)` | ✅ |

## Environment Comparison

| Setting | Dev | Stage | Prod |
|---|---|---|---|
| Tier 1 replicas | 1 | 2 | 3 |
| PDB minAvailable | — | 1 | 2 |
| Zone spread | ❌ | ❌ | ✅ |
| Load generator | ✅ (50 users, 5/s, HTTP-only) | ✅ (50 users) | ❌ |
| Metrics, traces, logs | Shared Prometheus, Tempo, Loki | Shared Prometheus, Tempo, Loki | Shared Prometheus, Tempo, Loki |
| Optional local mock LLM + reviews | ✅ | ❌ | ❌ |

## Accessing Services (dev)

```bash
# Exposes storefront, shared Grafana, and shared Prometheus locally only.
scripts/expose-platform-uis.sh --environment dev

# Storefront: http://127.0.0.1:8081
# Grafana:    http://127.0.0.1:3000
# Prometheus: http://127.0.0.1:9090
# Use Grafana Explore's Tempo datasource to inspect distributed traces.
```

## Upgrading the Upstream Chart

1. Check the latest version at: https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-demo
2. Update `targetRevision` in `gitops/bootstrap/applications-appset.yaml`
3. Review the upstream changelog for breaking values changes
4. Test in dev first — Argo CD syncs automatically after push
5. Promote to staging → prod after validation

## Future Improvements

| Phase | Enhancement |
|---|---|
| Phase 6 | Mirror images to Artifact Registry; use Git SHA tags |
| Phase 7 | Add Kyverno policies for resource limit enforcement |
| Phase 8 | Add workload-owned dashboards and alerts after live telemetry discovery |
| Phase 9 | Expose frontend via GKE Gateway with TLS |
| Phase 10 | Argo Rollouts canary for frontend deployments |
| Phase 11 | HPA for frontend, checkout; KEDA for Kafka consumers |
