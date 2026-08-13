# GKE-managed metrics API

GKE installs and reconciles the cluster metrics API (`metrics.k8s.io`) as a
managed addon. The platform must not install the upstream `metrics-server`
chart alongside it: both use the `metrics-server` Service and
`system:metrics-server` ClusterRole, which causes GitOps drift and can make a
chart-managed Deployment serve no traffic.

Use the GKE-managed API for HorizontalPodAutoscalers and `kubectl top`. Verify
it with:

```bash
kubectl top nodes
```

There is intentionally no `component.yaml` in this directory, so the platform
ApplicationSet does not create a competing Helm application.
