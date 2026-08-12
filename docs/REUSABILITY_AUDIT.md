# Reusability Audit

**Audit date:** 2026-08-12  
**Scope:** current worktree, before the generic-platform refactor  
**Status:** inspection only; this document is the only requested deliverable

## Executive summary

This repository is currently an OTel Demo platform implementation with a reusable-looking Terraform foundation around it. The stated target is a generic GCP DevSecOps platform, but the deployable path is still application-specific:

```text
GitHub Actions (one custom OTel Collector build)
  -> Artifact Registry convention
  -> ArgoCD ApplicationSet for opentelemetry-demo
  -> upstream OpenTelemetry Helm chart + OTel-specific values
  -> OTel Demo namespaces and service assumptions
```

The repository contains useful platform foundations—GCP project/API enablement, VPC networking, NAT, firewall, GKE, service accounts, Artifact Registry, GitHub WIF, ArgoCD bootstrap, External Secrets, and CI security actions—but many advertised platform components are only documented or planned. There are no actual checked-in manifests for Argo Rollouts, Kyverno/OPA policy enforcement, image verification admission, Prometheus/Grafana/Loki platform deployments, a platform-owned OpenTelemetry Collector, or workload-independent security/observability composition.

The principal migration constraint is architectural: Terraform currently provisions infrastructure and also bootstraps ArgoCD, which is appropriate, but the GitOps layer has an OTel-specific ApplicationSet, namespaces, source repositories, values schema, and CI image-update script. The generic platform needs a data-driven workload contract and must keep workload definitions outside platform components.

## Inspection scope and repository state

- The repository contains **808 files** in the current filesystem inventory, approximately **1.6 GiB**.
- `demo-application/opentelemetry-demo` contains **598 files** and is a large vendored/upstream workload tree with application source, Dockerfiles, compose files, telemetry schema, tests, generated code, images, fonts, and build artifacts.
- Platform/control-plane files outside that workload were read, including all root files, Terraform source, GitOps manifests, CI workflows/actions, bootstrap scripts, and existing architecture/ADR/inventory documentation. The OTel tree was inventoried as workload material and its control/configuration surface was identified; it is not a platform dependency that should be preserved in the target design.
- The worktree was already dirty before this audit. Existing modifications include `.github/workflows/terraform.yaml`, bootstrap files, all three environment Terraform roots, several GKE files, service-account files, and untracked `AGENTS.md`, `terraform/modules/gke/moved.tf`, and `terraform/modules/gke/versions.tf`. These changes were preserved.
- Local generated Terraform/provider/state/plan material exists under `terraform/environments/*/.terraform`, including a state file and plan output. These were not treated as source-of-truth platform code and were not modified. Their presence should be reviewed for accidental publication and secret exposure.

## Current architecture

### Intended architecture

The documentation describes a private regional GKE platform on GCP:

1. `bootstrap/bootstrap.sh` creates a Terraform state bucket, a Terraform service account, APIs, and IAM.
2. Terraform environment roots compose reusable modules for project services, networking, Cloud Router/NAT, firewall, service accounts, GKE, ArgoCD bootstrap, Artifact Registry, and GitHub WIF.
3. The ArgoCD bootstrap module installs ArgoCD and applies a root Application.
4. ArgoCD discovers bootstrap manifests and generates platform/application Applications.
5. GitHub Actions builds and scans images, writes to Artifact Registry, and updates GitOps.

### Effective architecture today

The effective Kubernetes deployment path is narrower:

- The root Application points at `gitops/bootstrap`.
- Bootstrap contains fixed platform namespaces, ArgoCD Projects, and two ApplicationSets.
- The platform ApplicationSet is currently configured for `dev` only because cluster-scoped resources are not safely isolated between environments on one cluster.
- The application ApplicationSet is also currently configured for `dev` only and directly selects the upstream `opentelemetry-demo` chart.
- The application values are OTel chart values keyed by OTel component names (`frontend`, `cart`, `checkout`, `flagd`, `kafka`, and so on), not a generic workload contract.
- The only local application Dockerfile is `applications/otel-collector/Dockerfile`; it is itself an OTel-specific custom collector image.
- The CI build matrix contains only `otel-collector-custom` and the security/release workflows reconstruct that same image reference.

The README advertises Istio, Chaos Mesh, Loki, Jaeger, policy enforcement, Binary Authorization, SLOs, and Backup for GKE, but the file inventory does not show deployable implementations for most of them.

## Current directory structure

```text
.
├── .github/
│   ├── actions/                    # Reusable Docker, GCP auth, security actions
│   ├── scripts/                    # OTel-oriented image-tag updater
│   └── workflows/                  # build, CI, release, security, Terraform
├── applications/otel-collector/    # One OTel-specific Dockerfile
├── bootstrap/                      # One-time GCP/Terraform state bootstrap
├── demo-application/
│   └── opentelemetry-demo/         # Large vendored example workload
├── docs/                           # Architecture, ADRs, phase plans, runbooks
├── gitops/
│   ├── bootstrap/                  # Namespaces, Projects, ApplicationSets
│   ├── applications/               # OTel Demo values and README
│   ├── environments/               # Three currently unused/common value dirs
│   └── platform/                   # ESO, metrics-server, priority classes
├── terraform/
│   ├── environments/{dev,stage,prod}/
│   └── modules/                    # Reusable GCP modules
├── helm/                           # Directory exists; no chart files found
├── monitoring/                     # Directory exists; no files found
├── networking/                     # Directory exists; no files found
├── security/                       # Directory exists; no files found
├── sre/                            # Directory exists; no files found
├── chaos/                          # Directory exists; no files found
├── output/                         # Local generated output; ignored by Git
└── scripts/                        # Directory exists; no files found
```

## Existing reusable components

### Terraform modules

| Module | Current responsibility | Reusability assessment |
|---|---|---|
| `project` | Enables GCP APIs | Platform-reusable, but API set is a fixed platform policy and `labels` is unused by resources. |
| `networking` | VPC, GKE, management and proxy subnets, secondary ranges | Good boundary, but subnet names, range names, CIDR defaults, routing mode, MTU, and descriptions are fixed. |
| `cloud-router` | Regional Cloud Router | Reusable shape; region/router defaults remain environment-specific. |
| `nat` | Cloud NAT | Reusable shape; NAT name/region defaults are fixed. |
| `firewall` | Internal/control-plane firewall rules | Reusable shape; internal CIDR default and rule semantics need explicit policy inputs. |
| `gke` | Private regional GKE cluster, node pools, autoscaling, logging/monitoring, Workload Identity | Strongest platform module. It still contains platform policy defaults and has known duplicate-WI history documented in `CODE-AUDIT-REPORT.md`. |
| `service-accounts` | GKE node, ArgoCD, External Secrets, GitHub Actions service accounts and IAM | Useful boundary, but account IDs and permissions are fixed; secret access is only a set of secret IDs, not a broader data-driven identity model. |
| `artifact-registry` | Docker repository and reader/writer IAM | Reusable shape, but repository ID and region are defaulted to current project conventions. |
| `github-wif` | Workload Identity Federation pool/provider and GitHub principal binding | Reusable concept, but GitHub repository and naming are caller inputs only at the root; least-privilege workflow/ref constraints need review. |
| `argocd-bootstrap` | Helm install, Kubernetes provider setup, root Application, GCP/KSA bindings | Platform-reusable concept, but it embeds ArgoCD-specific service accounts/namespaces and currently couples ESO/ArgoCD access into bootstrap. |
| `dns` | No implementation; only `.gitkeep` | Planned, not reusable code. |
| `monitoring` | No implementation; only `.gitkeep` | Planned, not reusable code. |

### CI reusable actions

- `.github/actions/docker-build`: generic multi-arch Buildx action with cache and provenance/SBOM flags.
- `.github/actions/gcp-auth`: generic WIF wrapper, but defaults to the current region hostname.
- `.github/actions/security-scan`: reusable Syft/Trivy/Cosign action with configurable failure and signing behavior.
- `.github/scripts/update-image-tag.sh`: not generic in practice; it assumes a fixed region, repository, and simple image-reference replacement in `gitops/`.

### GitOps reusable patterns

- ArgoCD root Application and App-of-Apps/ApplicationSet patterns are good foundations.
- ArgoCD Projects attempt source, destination, and cluster-resource isolation.
- Sync waves, automated sync, self-heal, prune, retry, and multi-source Helm values are useful patterns.
- The patterns are not yet parameterized: the generated application is named `otel-demo`, uses the OTel chart repository, and targets OTel namespaces and values.

## OpenTelemetry-specific coupling

### Runtime and GitOps coupling

| Location | Coupling |
|---|---|
| `gitops/bootstrap/applications-appset.yaml` | ApplicationSet name, generated Application name, chart repository, chart name, release name, values paths, namespace, and list element are all OTel Demo-specific. |
| `gitops/bootstrap/namespaces.yaml` | Creates `otel-demo-dev`, `otel-demo-stage`, and `otel-demo-prod`; these are workload-owned namespaces hardcoded in platform bootstrap. |
| `gitops/bootstrap/projects.yaml` | Application source repositories include the OTel Helm repository; destinations include OTel namespaces; descriptions explicitly name OTel Demo. |
| `gitops/applications/opentelemetry-demo/values/base.yaml` | Encodes the upstream OTel chart schema and a complete component inventory, resource sizing, node selectors, feature flags, and OTel environment variables. |
| `gitops/applications/opentelemetry-demo/values/{dev,stage,prod}.yaml` | Encodes OTel component replica counts, load-generator behavior, Valkey/Kafka, Jaeger/Prometheus/Grafana subcharts, and OTel service names. |
| `gitops/applications/opentelemetry-demo/README.md` | Operations and port-forward examples use OTel service names and namespaces. |
| `.github/workflows/build.yaml` | Build matrix contains only `otel-collector-custom` and the only build context is the OTel collector. |
| `.github/workflows/security.yaml` | Image discovery, digest, SBOM, scan, signing, and provenance all reconstruct `otel-collector-custom`. |
| `.github/workflows/release.yaml` | Release loop contains only `otel-collector-custom`. |
| `.github/workflows/ci.yaml` | Helm validation explicitly references the OTel chart and OTel value files. |
| `.github/scripts/update-image-tag.sh` | Example and intended behavior are OTel image updates; no generic workload/image contract exists. |
| `applications/otel-collector/Dockerfile` | Image base, labels, and registry comments identify OpenTelemetry. |
| `terraform/environments/*/locals.tf` | Labels use `project = "otel-demo"`; dev sizing comments calculate capacity for OTel Demo service counts. |
| `terraform/environments/*/main.tf` | Cluster name is `otel-${var.environment}-gke`; ArgoCD/GitHub repository values are hardcoded to the current repository. |
| `README.md` and phase docs | The repository identity, architecture, roadmap, and examples treat OTel Demo as the platform workload rather than an example consumer. |
| `renovate.json` | OTel Demo is a special dependency and the current GitHub user is an assignee/reviewer. |

### OTel coupling inside the vendored workload

`demo-application/opentelemetry-demo` is an application source tree, not a reusable platform component. It contains the Astronomy Shop services, service-specific Dockerfiles, compose environments, telemetry schema, generated protobufs, frontend assets, load generator, collector configurations, and tests. It should be retained only as an example workload (or moved to a separately versioned example repository/subtree) and must not be imported by Terraform, platform GitOps, policy, or shared observability configuration.

## Hardcoded values found

The following catalog covers hardcoded values in executable/platform configuration and the important documentation/configuration copies of those values. Values inside the upstream OTel application are workload-owned and are intentionally not listed as platform inputs.

### Project, identity, repository, and ownership

- GCP project ID `valiant-house-502004-k2` appears in all three `terraform.tfvars` files and `gitops/platform/external-secrets.yaml`.
- GitHub owner/repository `devSatym/gcp-platform-engineering` and URL `https://github.com/devSatym/gcp-platform-engineering.git` appear in all environment roots, GitOps Projects/ApplicationSets, and docs.
- Renovate assignee/reviewer `devSatym` is hardcoded in `renovate.json`.
- Terraform labels hardcode `team = "platform"`, `project = "otel-demo"`, `managed-by = "terraform"`, and `owner = "satyam"`.
- Service-account IDs are fixed as `sa-gke-nodes`, `sa-argocd`, `sa-external-secrets`, `sa-github-actions`, and bootstrap `sa-terraform`.
- The Terraform state bucket convention is `${PROJECT_ID}-tf-state`; backend prefixes are fixed as `dev/foundation`, `stage/foundation`, and `prod/foundation`.

### Environment, region, cluster, and repository defaults

- Region `asia-south1` is repeated in environment defaults/tfvars, module defaults, CI environment variables, scripts, docs, and examples.
- Environment defaults are `dev` in all three environment `variables.tf` files; stage/prod therefore depend on tfvars to correct the default.
- Cluster name is generated with the OTel-specific pattern `otel-${var.environment}-gke`.
- Node pools are fixed as `system-pool`, `general-pool`, and `spot-pool`; node labels are `workload=system|general|spot`; firewall/node tags are `gke-node`, `system-pool`, `general-pool`, and `spot-pool`.
- Artifact Registry defaults are region-local Docker registry, repository ID `platform-docker`, and the image path convention `${project}/platform-docker/${service}`.
- Network resource names and range names are fixed as `platform-vpc`, `gke-subnet`, `management-subnet`, `proxy-subnet`, `gke-pods`, and `gke-services`.

### Network and GKE policy values

- VPC routing is `REGIONAL`; MTU is `1460`.
- Primary/secondary CIDRs are `10.0.0.0/20`, `10.0.16.0/24`, `10.0.17.0/24`, `10.10.0.0/16`, and `10.20.0.0/20`; firewall internal CIDR defaults to `10.0.0.0/16`.
- Default node machine types and sizing are `e2-medium`, `e2-standard-4`, and `e2-standard-2`; disk sizes are 50/80/50 GiB; min/max counts are 1/2, 1/3, and 0/2 per zone in dev sizing.
- Cluster maintenance window timestamps, release-channel/network-policy choices, and node-pool labels/taints are fixed in `terraform/modules/gke` and environment roots.
- Stage/prod currently duplicate much of dev networking and GKE configuration, while their files omit or rely on module defaults for some inputs. Existing `docs/CODE-AUDIT-REPORT.md` records these inconsistencies.

### GitOps values

- Fixed namespaces include `argocd`, `platform-system`, `observability`, `security`, `networking`, `applications`, `kube-system`, `istio-system`, `istio-ingress`, `kyverno`, `falco`, and OTel namespaces.
- Platform chart versions include External Secrets `0.12.1` and metrics-server `3.12.2`.
- The OTel application chart is pinned to `0.40.9` in the ApplicationSet comments/elements.
- OTel values hardcode component names, replica counts 1/2/3, node selectors, load-generator settings, storage sizes 5/20/50 GiB, Prometheus retention `30d`, and Grafana `adminPassword: "admin"`.
- The stage load generator points to `http://otel-demo-frontend-proxy:8080`.
- GitOps source revision is `main`; the root Application and generated Applications use fixed branch/repository assumptions.

### CI and security values

- Build and security workflows hardcode the `otel-collector-custom` service, OTel Dockerfile/context, `asia-south1-docker.pkg.dev`, and `platform-docker`.
- Build targets are `linux/amd64,linux/arm64`; image tags use `sha-{short-sha}` and `build-{run-number}`.
- CI tool versions include Helm `3.14.0`, Terraform `1.9.0`, TFLint `0.50.3`, Cosign `v2.4.0`, and Trivy `v0.50.1` in scripts/actions.
- Security policy thresholds are CRITICAL fail / HIGH configurable warning, and the workflow permissions include broad contents/packages/security-events capabilities.
- Cosign keyless signing, Syft CycloneDX/SPDX, Trivy SARIF, and SLSA attestation are present as workflow intent, but their image selection is not data-driven.

## Duplicated dev/stage/prod configuration

### Terraform duplication

Each environment has its own `backend.tf`, `locals.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars`, `variables.tf`, and `versions.tf`. The three `main.tf` files repeat the full module composition, resource names, CIDRs, node-pool definitions, GitHub repository, and ArgoCD wiring. The environment roots should instead be thin instantiations of one composition module with structured environment data.

Notable divergence:

- Dev has a detailed `local.sizing` object; stage/prod do not have the same sizing source.
- Stage/prod headers and defaults still say `dev` in several files.
- Dev explicitly passes network CIDRs and firewall CIDR; stage/prod have historically omitted some of those inputs or relied on module defaults.
- Prod has an authorized-network entry absent from the comparable dev/stage root.
- All three tfvars files contain the same project and region, differing only in environment.

### GitOps duplication

- `gitops/applications/opentelemetry-demo/values/base.yaml` is shared, but the three environment files repeat the entire OTel component inventory and differ by replica/storage/load-generator settings.
- Namespaces are repeated as three OTel-specific resources.
- ApplicationSet list entries are intended to repeat environments but currently only enable dev.
- `gitops/environments/{dev,stage,prod}/values-common.yaml` exists as a second environment-value location, but the current ApplicationSet consumes the application-specific values directory instead; this is an architectural ambiguity.

## Current Terraform module boundaries and ownership

Terraform currently has a sensible dependency graph:

```text
project -> networking -> cloud-router -> nat
                    \-> firewall
project -> service-accounts -> gke
networking + service-accounts + nat -> gke
gke -> argocd-bootstrap
project -> artifact-registry
project -> github-wif
```

Recommended ownership boundary for the target remains:

- Terraform: GCP APIs, VPC/subnets/NAT/firewall, GKE, node pools, Artifact Registry, IAM, GitHub WIF, state, and the minimal ArgoCD bootstrap handoff.
- ArgoCD/GitOps: ArgoCD Projects/ApplicationSets, platform operators, observability, security policies, namespaces/tenants, workload Applications, Helm values, Rollouts resources, and ordinary Kubernetes resources.
- CI: build/test/scan/SBOM/sign/attest and publish immutable image metadata; it should propose or update workload GitOps data through a controlled contract.
- Workload repositories/charts: application source, chart templates, service-specific values, image build definitions, and workload-specific dashboards/alerts where needed.

Known implementation concerns to carry into migration:

- Existing docs identify duplicate Workload Identity bindings between `gke/workload_identity.tf` and `argocd-bootstrap/main.tf`.
- Existing docs identify missing root provider declarations in environment versions files, a provenance digest/tag bug, release artifact lookup issues, and other CI/bootstrap issues.
- Terraform state/plan artifacts are present locally and need repository hygiene checks.
- `argocd-bootstrap` uses provider/kubectl/Helm bootstrap mechanics that should be minimized and clearly separated from normal Kubernetes reconciliation.

## Current GitOps architecture

The architecture is App-of-Apps plus ApplicationSets:

```text
Terraform
  -> ArgoCD Helm install + root Application
     -> gitops/bootstrap
        -> namespaces.yaml
        -> projects.yaml
        -> platform-appset.yaml
        -> applications-appset.yaml
           -> platform/ Applications
           -> OTel Demo Applications
```

Strengths:

- Git is intended to remain the Kubernetes source of truth.
- Automated sync, self-heal, prune, retries, sync waves, multi-source Helm values, and ArgoCD Projects are established patterns.
- Terraform does not attempt to manage ordinary application Deployments directly.

Gaps:

- Platform and workload environment generation are not driven by one typed environment/cluster catalog.
- Cluster-scoped platform resources are generated per environment even though the current architecture is effectively one cluster at a time; stage/prod are commented out rather than modeled cleanly.
- Workload namespaces are owned by platform bootstrap and named for OTel.
- There is no generic workload Application template consuming fields such as chart repository, chart, version, values, namespace, rollout strategy, host, secrets, or observability options.
- There is no generic Deployment/Argo Rollout capability model. The platform assumes the upstream chart’s native resource kinds.
- Platform directories named `observability`, `security`, `networking`, and `tenants` are documented but have no corresponding manifest implementation in the current inventory.

## Current CI architecture

### Present workflows

- `ci.yaml`: PR YAML/Markdown lint, OTel values syntax checks, Terraform format/validate/TFLint/Checkov, and Gitleaks.
- `build.yaml`: main-branch build/push, multi-arch Buildx, provenance/SBOM flags, then GitOps commit.
- `security.yaml`: workflow-run image reconstruction, Syft SBOM, Trivy scan, Cosign signing, and attestation intent.
- `release.yaml`: tag release and OTel Collector image retagging.
- `terraform.yaml`: separate Terraform plan workflow; existing audit documentation records duplicate-plan and other issues.

### CI limitations for the target

- No workload discovery/build contract; only one OTel Collector matrix entry exists.
- No generic chart lint/render test per declared workload.
- No policy test for rendered workload manifests.
- No reliable build-to-security artifact/digest handoff; security reconstructs an image from the current Git SHA.
- Image update is a shell text replacement rather than an immutable digest promotion model.
- CI commits directly to the GitOps tree from a build workflow, which can create races and mixes build and promotion responsibilities.
- WIF exists, but project/region/repository values and permissions are not consistently configuration-driven.
- The required future platform checks—Rollouts validation, policy tests, `kubectl apply --dry-run=client`, and generic Helm lint—are not wired for arbitrary workloads.

## Missing components required by the target architecture

### Infrastructure and isolation

- A single reusable environment composition module and data-driven dev/staging/prod catalog.
- Explicit choice and implementation for one cluster per environment versus shared cluster with namespace/tenant isolation. Current manifests assume one cluster per environment but the Terraform/GitOps shape does not enforce or clearly model that.
- Environment-specific projects or at least explicit project/cluster/network inputs, non-overlapping CIDRs, naming strategy, and state prefixes.
- GKE security controls: authorized networks/access path, NetworkPolicy/Dataplane V2 decision, shielded/secure boot settings, node hardening, binary authorization integration, backup, and upgrade policy.

### GitOps and workload contract

- A generic workload schema/catalog, for example `platform/workloads/<workload>.yaml`, containing name, source, chart, version, values, namespace, host, environment overlays, rollout strategy, observability, and secret references.
- A generic ApplicationSet generator/template that renders one Application per workload/environment/cluster.
- A clear ownership rule for namespaces, service accounts, network policies, resource quotas, limit ranges, and workload-specific resources.
- Separate platform applications from workload applications and from the OTel example.
- Generic ordinary Deployment support plus optional Argo Rollouts integration, without requiring every chart to use Rollouts.
- A promotion model based on immutable image digests and pull requests, not uncontrolled build-job commits.

### DevSecOps and Kubernetes security

- Kyverno or Gatekeeper policy installation and policies for required resources/limits, non-root, seccomp, capabilities, image provenance/signature, registries, namespaces, and disallowed host access.
- Image scanning and SBOM generation for every workload image, with policy thresholds and artifact retention.
- Cosign keyless signing/verification with digest-based references and admission enforcement where practical.
- Binary Authorization/GKE admission integration if selected, with a clear relationship to Kyverno signature verification.
- External Secrets platform deployment plus SecretStore/ClusterSecretStore strategy, secret naming conventions, least-privilege access, and workload references without committed values.
- NetworkPolicies generated from workload declarations or provided by charts, with default-deny strategy and platform exceptions.

### Observability and progressive delivery

- Platform-owned Prometheus, Grafana, Loki, and OpenTelemetry Collector deployments in `gitops/observability`.
- A generic telemetry contract: OTLP endpoints, service/environment/resource attributes, scrape annotations/PodMonitors, log labels, trace sampling, and optional dashboards/alerts.
- Storage, retention, tenancy, and environment isolation for metrics/logs/traces.
- Argo Rollouts controller, analysis templates, metric providers, and examples that are opt-in per workload.
- Standard health probes, PodDisruptionBudgets, topology spread, autoscaling, and rollout defaults that are configurable rather than OTel-component-specific.

## Proposed target repository structure

```text
.
├── platform/
│   ├── contracts/
│   │   ├── workload.schema.json       # Versioned workload contract
│   │   └── environment.schema.json
│   ├── catalog/
│   │   ├── environments.yaml          # dev/staging/prod cluster metadata
│   │   └── workloads.yaml             # enabled workloads and policy options
│   ├── helm/
│   │   ├── workload-application/      # Generic ArgoCD Application template data
│   │   ├── workload-namespace/         # Optional namespace/quotas/limits
│   │   └── rollout-resources/          # Optional Rollout/PDB/HPA helpers
│   └── policies/                       # Policy sources and exceptions
├── terraform/
│   ├── modules/                        # GCP-only reusable modules
│   ├── platform/                       # One composition root
│   └── environments/{dev,staging,prod}/# Thin data-only roots
├── gitops/
│   ├── bootstrap/                      # Root app, projects, cluster registration
│   ├── platform/                       # ArgoCD, ESO, metrics-server, controllers
│   ├── observability/                  # Prometheus/Grafana/Loki/OTel Collector
│   ├── security/                       # Kyverno/Gatekeeper/Falco/signature policy
│   ├── networking/                     # Gateway/Ingress/network policy integrations
│   ├── tenants/                        # Namespace-level isolation primitives
│   ├── workloads/                      # Generated/templated generic workload apps
│   └── examples/opentelemetry-demo/    # Only one workload declaration/example
├── workloads/
│   ├── opentelemetry-demo/             # Example chart/values or external reference
│   ├── online-boutique/                # Future example declaration
│   └── README.md                       # Workload onboarding contract
├── .github/
│   ├── actions/                        # Generic auth/build/scan/promotion actions
│   └── workflows/                      # reusable CI, platform CI, promotion
└── docs/
    ├── architecture/
    ├── contracts/
    ├── operations/
    └── migration/
```

The exact layout may differ, but the invariant should be that Terraform modules, platform GitOps, security policy, and observability do not import or name a workload. A workload should be onboarded by adding a contract record, chart/values reference, and—only when needed—workload-owned policy exceptions.

## Migration sequence

1. **Freeze and baseline.** Preserve this audit, record current Terraform/GitOps state safely, remove generated artifacts from any publishable path, and resolve the existing dirty-worktree ownership before broad changes.
2. **Define contracts first.** Specify schemas for environment, cluster, workload, image, secrets, observability, and rollout strategy. Validate them in CI.
3. **Separate example workload.** Move OTel-specific chart values and docs under an example workload boundary. Keep the demo deployable through the contract, not through platform names.
4. **Refactor Terraform composition.** Create one composition module; make environment roots data-only. Move all names, project IDs, regions, CIDRs, cluster names, repo URLs, labels, sizing, and state prefixes to environment inputs. Do not apply during this migration.
5. **Refactor bootstrap GitOps.** Make ArgoCD Projects, destinations, namespaces, and cluster registration environment-aware. Remove OTel namespaces and OTel source repositories from platform bootstrap.
6. **Implement generic workload generation.** Generate Applications from workload/environment data. Support external Helm repositories, Git charts, values files, namespace, host, secrets, observability, and optional Rollouts.
7. **Install platform controllers.** Add Argo Rollouts, External Secrets, Prometheus/Grafana/Loki/OTel Collector, and chosen security controllers as platform Applications with pinned versions and health/sync ordering.
8. **Implement policy and supply-chain gates.** Add rendered-manifest tests, Kyverno/Gatekeeper policies, digest-only promotion, SBOM publication, scanning, keyless signing, and admission verification where practical.
9. **Generalize CI/CD.** Replace the fixed build matrix with workload metadata or reusable workflow inputs. Separate build, attest, and promotion; update GitOps by PR or a signed promotion mechanism.
10. **Migrate OTel Demo through the contract.** Verify ordinary Deployment/chart behavior, observability defaults, secrets, policy compliance, and optional Rollout behavior.
11. **Add a second workload.** Onboard Online Boutique or a small synthetic Helm workload without changing Terraform, platform Applications, security policies, or observability stack. This is the acceptance test for genericity.
12. **Delete/rename legacy paths.** Remove OTel assumptions from shared files only after both workloads pass validation and the old ApplicationSet path is no longer referenced.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Terraform state address changes during module consolidation | Unplanned replacement or loss of resources | Use explicit `moved` blocks/import plans, review plans, and never apply automatically. |
| One-cluster versus three-cluster ambiguity | Cluster-scoped resource conflicts and weak environment isolation | Decide topology first; model clusters/environments explicitly and test ApplicationSet destinations. |
| Generic chart contract cannot represent every chart | Onboarding becomes a collection of exceptions | Keep the contract minimal, permit chart-native values, and make extensions explicit/versioned. |
| Rollout conversion breaks charts that expect Deployments | Failed syncs or unavailable services | Default to ordinary Deployments; enable Rollouts only for compatible workloads and test generated manifests. |
| Security policies block legitimate third-party charts | Slow or impossible onboarding | Start in audit mode, publish exceptions with owners/expiry, then enforce progressively. |
| OTel values are accidentally copied into platform defaults | New workloads inherit invalid settings | Enforce path ownership and CI checks that reject workload names in shared platform files. |
| CI promotion races or recursive commits | Incorrect image deployed or workflow loops | Promote immutable digests through PRs, use concurrency controls, and separate build/security/promotion artifacts. |
| External Secrets permissions are too broad | Secret disclosure across environments | Use per-environment projects/secrets, namespace-scoped stores where possible, and explicit IAM bindings. |
| Existing generated state/plan output leaks sensitive data | Credential or infrastructure disclosure | Keep ignored, scan history and working tree, rotate anything exposed, and use remote state securely. |
| Documentation overstates implementation | Operators rely on nonexistent controls | Update claims as components become real and add executable validation for each advertised capability. |

## Delete, retain, rename, and refactor decisions

### Retain

- Terraform module concept and GCP foundations: project/API, networking, router/NAT, firewall, GKE, Artifact Registry, GitHub WIF, and service-account boundaries.
- ArgoCD bootstrap concept, AppProject isolation, ApplicationSet/App-of-Apps patterns, sync waves, and GitOps source-of-truth rule.
- Generic CI actions for GCP authentication, Docker build, SBOM, scanning, and signing after their digest/artifact handoffs are corrected.
- `demo-application/opentelemetry-demo` as an explicitly isolated example workload, subject to size/licensing/repository-management review.
- ADRs and architecture documentation after rewriting workload-specific assumptions.

### Refactor

- All three Terraform environment roots into one composition module plus data-only environment inputs.
- Names, IDs, regions, domains, namespaces, repository URLs, image repositories, labels, and sizing into typed variables/catalogs.
- `gitops/bootstrap/applications-appset.yaml` into a generic workload ApplicationSet.
- `gitops/bootstrap/namespaces.yaml` and `projects.yaml` into environment/tenant-aware, workload-independent resources.
- OTel values into `gitops/examples` or `workloads/opentelemetry-demo`.
- CI build/security/release workflows into workload-parameterized reusable workflows using immutable image digests.
- `update-image-tag.sh` into a contract-aware promotion tool or remove it in favor of PR-based digest updates.
- `gitops/environments/*/values-common.yaml` and application values into one unambiguous layering model.
- Existing platform README/roadmap claims so they describe implemented versus planned components accurately.

### Rename

- `stage` should be standardized as `staging` in the new contract, with an explicit migration alias if existing state/paths require it.
- `applications/opentelemetry-demo` and OTel-specific docs should move under an `examples` or `workloads` boundary.
- `project`/`owner` labels should become caller-provided organizational metadata, not repository identity.
- `otel-${environment}-gke` should become a caller-provided cluster naming convention.

### Delete after migration verification

- OTel-specific ApplicationSet and fixed OTel namespace resources.
- OTel-specific assumptions from shared Terraform, CI, security, observability, and platform docs.
- Empty placeholder directories if they are not replaced by real platform components.
- Local generated state/plan/output artifacts from the repository workspace or any publishable artifact path.
- Duplicate environment Terraform files and duplicate values once the new composition and contract are proven.

## Acceptance criteria for the future refactor

The platform refactor should not be considered complete until all of the following are true:

1. A second arbitrary Helm workload can be added by configuration and workload-owned values without editing Terraform modules or platform security/observability manifests.
2. Dev, staging, and prod are generated from the same Terraform composition and GitOps templates, with differences represented only by validated configuration.
3. Terraform plans only GCP/bootstrap responsibilities; ArgoCD owns normal Kubernetes resources.
4. Both ordinary Kubernetes Deployments and opt-in Argo Rollouts are supported.
5. Every image has an immutable digest, scan result, SBOM, provenance, and—where enabled—signature verification outcome.
6. Secrets are external references only; no secret values are committed.
7. Platform policies cover arbitrary workloads and exceptions are explicit, reviewable, scoped, and expiring.
8. Metrics, logs, traces, Prometheus, Grafana, Loki, and the OpenTelemetry Collector are platform services with workload-neutral integration points.
9. CI runs Terraform format/validate, Helm lint/template, YAML lint, client-side Kubernetes dry-run, contract validation, policy tests, secret scanning, and relevant image security checks.
10. No destructive command, Terraform apply, cluster deletion, or uninstall is part of the migration automation.

