# OpenTelemetry Demo — Platform Engineering Deployment

This directory contains our production overlay on top of the upstream [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) (Astronomy Shop) Helm chart.

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
| **T3 Platform** | OTel Collector, Prometheus, Grafana, Jaeger, Flagd | general/system | `platform-critical (1000)` | ✅ (collector) |
| **T4 Non-crit** | Load Generator | **spot** | `non-critical (100)` | ❌ |
| **Data** | Valkey, PostgreSQL, Kafka | general | `business-critical (900)` | ✅ |

## Environment Comparison

| Setting | Dev | Stage | Prod |
|---|---|---|---|
| Tier 1 replicas | 1 | 2 | 3 |
| PDB minAvailable | — | 1 | 2 |
| Zone spread | ❌ | ❌ | ✅ |
| Load generator | ✅ (10 users) | ✅ (50 users) | ❌ |
| Prometheus persistence | ❌ | 20Gi | 50Gi (30d) |
| Grafana persistence | ❌ | 5Gi | 20Gi |
| OpenSearch | ❌ | ❌ | ❌ (Phase 8) |

## Accessing Services (dev)

```bash
# Storefront (frontend)
kubectl port-forward svc/otel-demo-frontendproxy -n opentelemetry-demo-dev 8080:8080
# Open http://localhost:8080

# Grafana dashboards
kubectl port-forward svc/otel-demo-grafana -n opentelemetry-demo-dev 3000:80
# Open http://localhost:3000 — admin/admin

# Jaeger traces
kubectl port-forward svc/otel-demo-jaeger-query -n opentelemetry-demo-dev 16686:16686
# Open http://localhost:16686

# Prometheus metrics
kubectl port-forward svc/otel-demo-prometheus-server -n opentelemetry-demo-dev 9090:80
# Open http://localhost:9090
```

## Upgrading the Upstream Chart

1. Check the latest version at: https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-demo
2. Update `targetRevision` in `gitops/bootstrap/applications-appset.yaml`
3. Review the upstream changelog for breaking values changes
4. Test in dev first — ArgoCD syncs automatically after push
5. Promote to staging → prod after validation

## Future Improvements

| Phase | Enhancement |
|---|---|
| Phase 6 | Mirror images to Artifact Registry; use Git SHA tags |
| Phase 7 | Add Kyverno policies for resource limit enforcement |
| Phase 8 | Externalize Prometheus/Grafana/Jaeger to `observability/` |
| Phase 9 | Expose frontend via GKE Gateway with TLS |
| Phase 10 | Argo Rollouts canary for frontend deployments |
| Phase 11 | HPA for frontend, checkout; KEDA for Kafka consumers |
