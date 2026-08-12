# GitOps architecture

Git is the desired-state source of truth after ArgoCD is bootstrapped by
Terraform. Terraform installs ArgoCD and applies the project definitions and
root Application; ArgoCD then manages the remaining Kubernetes state.

## Ownership layout

```text
gitops/
├── bootstrap/                 # root-discovered namespaces and ApplicationSets
├── projects/                  # ArgoCD AppProjects and ownership boundaries
├── platform/                  # platform domain documentation and shared core
├── external-secrets/          # ESO component registration and values
├── metrics-server/            # metrics-server component registration and values
├── security/                  # reserved Kyverno/policy domain
├── progressive-delivery/      # reserved Argo Rollouts domain
├── observability/             # reserved metrics/logs/traces domain
├── workloads/                 # workload registrations and chart values
└── environments/              # cluster destinations and environment policy
    ├── dev/config.yaml
    ├── staging/config.yaml
    └── prod/config.yaml
```

Platform directories contain shared cluster services. Workload directories
contain only a workload contract and workload-owned values. Environment files
contain destinations and policy metadata; they do not contain application
templates.

## ApplicationSet model

`bootstrap/platform-appset.yaml` creates one Application for each platform
component and environment by combining component registrations with environment
configuration. `bootstrap/applications-appset.yaml` creates one Application for
each workload registration and environment using the same matrix pattern.

Adding a workload means adding `workloads/<name>/workload.yaml` and its values;
it does not require copying an Application manifest for every environment.

The workload contract supports:

- chart repository, chart, and pinned version;
- common and per-environment values files;
- workload namespace base name;
- progressive-delivery, observability, and External Secrets feature flags.

Workloads are added through registrations under `workloads/`; platform code does not name or implement any workload.

## Sync ordering

| Wave | Ownership | Purpose |
| --- | --- | --- |
| -3 | Terraform bootstrap | Installs ArgoCD and root Application |
| -2 | Bootstrap | Shared namespaces |
| -1 | Bootstrap/projects | AppProjects and ApplicationSets |
| 0 | Platform | External Secrets Operator and CRDs |
| 1 | Platform | Metrics-server and API aggregation |
| 2 | Workloads | Helm applications after platform foundations |

Security, progressive delivery, and observability are reserved domains at this
stage. Their controllers and policies are deliberately not installed by this
architecture-only change. When added, they should receive their own component
registrations and waves, with workload Applications remaining at a later wave.

## Boundary rules

- Terraform owns cloud infrastructure and ArgoCD bootstrap only.
- Platform owns shared controllers, CRDs, cluster policies, and shared telemetry.
- Workloads own chart identity, application services, ports, replicas, probes,
  resource requests, dashboards, and opt-in rollout behavior.
- Environments own destination clusters, namespace suffixing, and promotion
  policy metadata.
- Secrets are referenced through External Secrets; secret values and passwords
  are not committed.

The staging and production destination values are placeholders until ArgoCD
cluster credentials or reachable endpoints are configured. No manifest in this
change installs a new observability or security stack.
