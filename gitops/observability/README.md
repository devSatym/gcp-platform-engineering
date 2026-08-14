# Observability platform domain

The observability namespace hosts shared platform services, managed through
Argo CD component definitions. They do not depend on the OpenTelemetry Demo,
which keeps its own embedded telemetry stack as workload-owned example content.

## Components

- kube-prometheus-stack: Prometheus, Grafana, Kubernetes metrics, and standard
  cluster, namespace, workload, pod, and Kubernetes-resource dashboards.
- loki: shared log store.
- k8s-monitoring: Grafana Alloy collection for pod logs, node logs, and
  Kubernetes events.
- tempo: OTLP-native trace backend, with generic span metrics and service graphs.
- otel-collector: shared OTLP gateway for arbitrary workloads.

## Telemetry paths

Kubernetes and workload metrics -> Prometheus -> Grafana
Pods, nodes, and Kubernetes events -> Grafana Alloy -> Loki -> Grafana
Instrumented workloads -> OTLP -> OTel Collector -> Tempo -> Grafana

The shared collector exposes standard endpoints:

- OTLP/gRPC: otel-collector.observability.svc.cluster.local:4317
- OTLP/HTTP: http://otel-collector.observability.svc.cluster.local:4318

Workloads configure these endpoints through their own configuration; no
workload service names exist in platform values. OTLP metrics are exposed to
Prometheus, logs go to Loki, and traces go to Tempo.

## Dashboards

Grafana receives standard kube-prometheus-stack dashboards plus a generic
Platform / Service Golden Signals dashboard. It shows HTTP rate, error ratio,
p95 latency, and running Pods whenever standard metric families are available.
Application-specific dashboards belong with their workload.

The platform also provisions the following reusable dashboards automatically
through GitOps when Grafana starts:

- **Platform / Overview** — cluster readiness, resource use, target health,
  and firing alerts.
- **Platform / Telemetry Pipeline** — collector scrape health plus Loki and
  Tempo ingestion.
- **Platform / Logs and Events** — namespace-scoped logs, error signals, and
  Kubernetes warnings through Loki.
- **Platform / Traces and Service Graph** — Tempo span metrics and service
  graph metrics, with Grafana Explore for trace search.

They are loaded by Grafana's dedicated `platform` dashboard provider; Loki's
maintained dashboards are still discovered through the Grafana sidecar.

Loki also supplies its maintained dashboards, recording rules, alert rules,
and ServiceMonitor. Tempo and the Alloy operator are scraped by Prometheus.
The platform alert rules intentionally route only to Alertmanager's local UI;
configure a credential-backed receiver separately before enabling external
notifications.

## Trace backend decision

Tempo is the platform trace backend rather than Jaeger. It accepts OTLP
directly and provides Grafana-native querying alongside Prometheus and Loki,
which is simpler for this portfolio platform. The OpenTelemetry Demo's embedded
Jaeger chart is disabled, so Demo traces use this shared Tempo backend.

## Operating model

Loki and Tempo use persistent single-binary deployments appropriate for a
small portfolio cluster. Workload-facing protocols remain stable if a future
production profile moves to object storage and a distributed topology.
Grafana generates its own admin secret at install time; no credential is
committed to Git.
