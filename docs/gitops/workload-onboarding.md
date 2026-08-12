# Generic workload onboarding

Adding a Helm workload requires a registration under `gitops/workloads/` and,
only when needed, workload-owned values files. Terraform, GKE modules, ArgoCD
bootstrap, security, observability, and CI foundations remain unchanged.

## Registration schema

```yaml
workload:
  name: example-service
  namespace: example-service

  source:
    type: helm
    repoURL: https://example.invalid/charts
    chart: example-service
    path: ""
    targetRevision: 1.2.3

  destinations:
    dev:
      namespace: example-service-dev
    staging:
      namespace: example-service-staging
    prod:
      namespace: example-service-prod

  values:
    common: gitops/workloads/example-service/values/base.yaml
    environments:
      dev: gitops/workloads/example-service/values/dev.yaml
      staging: gitops/workloads/example-service/values/staging.yaml
      prod: gitops/workloads/example-service/values/prod.yaml

  syncWave: "2"

  progressiveDelivery:
    enabled: false
    strategy: deployment # deployment, canary, or blueGreen

  hostname:
    enabled: false
    value: example.invalid

  network:
    exposure: ClusterIP
    ingress:
      enabled: false
      gatewayClass: ""
      hostname: ""

  observability:
    enabled: true
    metrics: true
    logs: true
    traces: true

  secrets:
    enabled: false
    references: []
```

`source.type: helm` with `chart` set selects a remote Helm repository and chart.
For a chart stored in Git, set `type: git`, leave `chart` empty, and set
`path` to the chart directory. `targetRevision` is the chart version or Git
revision. Both source forms use the same generator and ownership boundaries.

The `destinations` map declares the namespace for each generated environment
Application. The current platform environment set is dev, staging, and prod;
the generator creates one Application for each registered workload and each
configured environment. Each key in `destinations` is an enabled deployment target. Remove a key when
a workload should not be deployed to that environment.

## Generated Application behavior

`gitops/bootstrap/applications-appset.yaml` uses an ApplicationSet matrix:

```text
workload registrations × environment configurations
                 │
                 ├── chart source and pinned revision
                 ├── common values + environment values
                 ├── destination namespace
                 ├── feature metadata labels
                 └── sync wave
```

Applications use the `workloads` ArgoCD project and are created with
`CreateNamespace`, server-side apply, automated self-healing, and pruning.
Promotion and stricter production rollout behavior are represented by the
environment/workload policy and progressive-delivery metadata; the platform
generator does not contain application names or chart assumptions.

## Example onboarding

```text
gitops/workloads/example-service/
├── workload.yaml
└── values/
    ├── base.yaml
    ├── dev.yaml
    ├── staging.yaml
    └── prod.yaml
```

After committing the registration and values, ArgoCD discovers it through the
existing ApplicationSet. No Terraform or platform manifest changes are
required. Secrets must be referenced through External Secrets metadata and
provided by the platform’s secret flow; secret values must not be committed.

## Ownership boundary

Workload owners control chart identity, values, application resources, service
ports, replicas, probes, resource requests, hostnames, and opt-in rollout or
telemetry metadata. Platform owners control ArgoCD, admission/security
controllers, shared observability, External Secrets, cluster policies, and
environment destinations. Neither side should encode assumptions about the
other’s application names or internal services.
