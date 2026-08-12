# Terraform and Workload Boundary

Terraform is intentionally aware that the platform will run Kubernetes
workloads. It must remain unaware of which workload is deployed.

## Terraform-owned capabilities

Terraform owns cloud and cluster foundations:

- enabled GCP APIs;
- VPCs, subnets, secondary ranges, routes, NAT, and firewall rules;
- GKE clusters, node pools, autoscaling, release channels, and cluster addons;
- Artifact Registry repositories and generic node/CI access;
- platform service accounts, IAM, GKE Workload Identity, and GitHub WIF;
- Secret Manager containers and access foundations;
- DNS zones and records that are platform-owned or supplied as infrastructure
  inputs;
- GKE logging, monitoring, and managed Prometheus integration;
- the one-time ArgoCD installation and root GitOps handoff.

These resources are parameterized by environment configuration. They do not
accept workload chart names, application service names, application ports,
Deployment names, replica counts, application dashboards, or application
specific scheduling rules.

## GitOps/workload-owned capabilities

The GitOps workload layer owns:

- workload chart identity, repository, path, and chart revision;
- namespaces selected through the workload contract;
- Helm values and environment overlays;
- Deployments, Services, Rollouts, HPAs, PDBs, probes, and application ports;
- workload-specific node selectors, affinities, tolerations, and resource
  profiles, subject to platform policy;
- hostnames and route backends requested through the platform contract;
- ExternalSecret references and application secret consumption;
- workload dashboards, alerts, metrics rules, and telemetry configuration.

Kyverno and other platform controllers validate these resources without
requiring Terraform to know their application identity.

## Legitimate exceptions

### GKE workload capacity and telemetry

GKE must know that pods, Services, and workload telemetry exist because it
allocates secondary IP ranges, enables workload metadata/identity, exports
workload logs, and can enable managed Prometheus. These are cluster-wide
capabilities and do not identify any workload.

### Generic node-pool capacity classes

Terraform may create node-pool labels and taints such as generic `system`,
`general`, or `spot` capacity classes. This describes infrastructure capacity,
not an application assignment. Workload GitOps values decide whether a pod is
compatible with a class, and policy may restrict that choice.

### Platform controller identities

Terraform creates identities for GKE nodes, ArgoCD, External Secrets Operator,
and GitHub Actions because those platform controllers need cloud permissions.
The ArgoCD bootstrap module contains fixed `argocd` and platform-system service
account bindings because those are part of the selected controller chart's
bootstrap contract. They are platform components, not workload identities.

### Artifact Registry access

Terraform creates a generic repository and grants GKE node read access and CI
write access. It does not create image repositories for individual services,
choose image tags/digests, or know which workload consumes an image.

### ArgoCD bootstrap repository

The Terraform-to-ArgoCD handoff requires the Git repository URL and the pinned
ArgoCD chart version. This identifies the platform GitOps source and controller
version, not a workload chart.

## Explicit non-exceptions

The following must never be added to Terraform modules or environment
composition:

- OpenTelemetry Demo, Online Boutique, or another workload name;
- workload Helm chart/repository/version;
- application Service or Deployment names;
- application ports or hostnames;
- application replica counts or PDB policy;
- application-specific node placement;
- workload dashboards or service-specific alert rules;
- workload image tags, digests, or per-service Artifact Registry paths.

If a future infrastructure feature appears to require one of these values,
the design must first attempt to expose a generic platform capability and pass
the workload value through GitOps instead. A new exception requires an ADR or
an update to this boundary document before implementation.
