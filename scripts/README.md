# Local UI access

After Terraform has successfully provisioned the cluster and Argo CD has
synchronized its Applications, run:

```bash
scripts/expose-platform-uis.sh --environment dev
```

The helper uses `kubectl port-forward --address 127.0.0.1`, so it does not
create public Services, load balancers, or ingress rules. It exposes Argo CD,
the OpenTelemetry Demo storefront, and the shared Grafana, Prometheus, and
Alertmanager UIs. Loki and Tempo are available through Grafana Explore. It
prints only endpoints, never credentials.

Pass `--context` to select a kubeconfig context or `--workload-namespace` if a
workload uses a non-standard namespace. Keep the command running while using
the UIs and press Ctrl-C to cleanly close all port-forwards.
