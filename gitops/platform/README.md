# Platform component ownership

This directory is reserved for platform-wide Kubernetes resources that are
not part of a business workload. Platform components are deployed by the
platform ApplicationSet in `bootstrap/platform-appset.yaml`.

Component domains have separate top-level directories so ownership and sync
ordering remain visible:

- `external-secrets/` — External Secrets Operator.
- `metrics-server/` — metrics API aggregation.
- `security/` — future Kyverno and reusable policy configuration.
- `progressive-delivery/` — future Argo Rollouts controller and shared config.
- `observability/` — future Prometheus, Grafana, Loki, and telemetry.

No business workload may be added here. Workload-specific values, service
names, dashboards, ports, and rollout choices belong under `workloads/`.
