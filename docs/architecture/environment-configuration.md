# Environment configuration model

The Terraform roots in `terraform/environments/dev`, `staging`, and `prod` all compose the same reusable `platform-environment` module. The roots provide values; modules provide implementation. No environment profile is encoded in a reusable module.

## Profile summary

| Concern | Dev | Staging | Prod |
| --- | --- | --- | --- |
| Cost profile | Low | Medium | High |
| Cluster locations | One configured zone | Three configured zones | Three configured zones |
| Baseline system capacity | One small node per pool baseline | One small system node per zone | Two larger system nodes per zone |
| General capacity | `e2-standard-2`, 1–2 per zone | `e2-standard-4`, 2–5 per zone | `e2-standard-4`, 2–8 per zone |
| Spot capacity | Optional, 0–1 | Optional, 0–2 | Optional, 0–3 |
| NAT ports per VM | 32 | 64 | 128 |
| Private control-plane endpoint | Disabled | Enabled | Enabled |
| Release channel | Regular | Regular | Stable |
| Managed Prometheus and supporting add-ons | Disabled where optional | Enabled | Enabled |
| Deletion protection | Disabled | Enabled | Enabled |
| Binary Authorization | Disabled | Disabled pending policy foundation | Enforced after singleton policy exists |
| Maintenance window | Provider default | Explicit weekday window | Explicit weekday window |

Counts are GKE autoscaling counts per configured zone. The values are starting profiles, not universal capacity recommendations; sizing should be changed from the environment tfvars after workload measurement.

## Why these differences exist

Dev minimizes spend and accepts reduced redundancy: one zone, smaller disks and machines, lower autoscaling ceilings, fewer optional managed add-ons, and no deletion protection. It remains private at the node/network layer and retains baseline security controls.

Staging intentionally resembles production’s three-zone topology and private endpoint access. It has enough general capacity for release validation and enables observability and supporting GKE add-ons. Its release channel remains Regular so upgrades can be exercised before production. Binary Authorization remains disabled until the project-level policy and signing workflow are provisioned.

Prod uses three zones, higher per-zone minimums, larger disks, a Stable release channel, private endpoint access restricted to the management subnet, deletion protection, explicit maintenance windows, and Binary Authorization enforcement. The production Binary Authorization setting requires a configured project singleton policy before apply; this repository does not silently invent that policy.

The CIDR ranges are intentionally non-overlapping between environments so environments can later be connected or inspected without route ambiguity. Project IDs, regions, zones, names, repository IDs, GitHub repository, DNS inputs, and chart inputs remain replaceable configuration values.

## Configuration boundary

Terraform environment configuration owns cloud capacity, isolation, network ranges, cluster security posture, registry foundations, IAM foundations, and lifecycle safeguards. It does not define a workload chart, service name, Deployment, application port, replica count, dashboard, or rollout strategy.

The requested “relaxed dev rollout” and “safer prod rollout” policies belong in GitOps workload/environment configuration. Dev can select a less conservative Argo Rollouts policy or ordinary Deployment; prod can require progressive delivery, analysis, approval, and stronger workload resource policy. Those settings must not be inferred from Terraform labels.

Likewise, stronger production resource expectations here mean node capacity and autoscaling headroom. Application requests, limits, probes, PDBs, and scheduling rules remain workload-owned.

## Operational prerequisites

- Replace all `replace-with-*` values before provisioning.
- Staging and prod private endpoints require the Terraform runner and ArgoCD bootstrap path to have private network reachability. A connected runner, bastion, or equivalent controlled access path is required.
- Prod Binary Authorization enforcement requires the project singleton policy and an image attestation/signing process.
- Workload-specific secrets remain in Secret Manager and are consumed through External Secrets; no secret value belongs in these tfvars files.

## Avoiding artificial differences

The ArgoCD chart version, Git repository input, core security defaults, workload identity, network policy, and generic platform composition are intentionally consistent. Only cost, availability, upgrade, lifecycle, and security posture settings differ where the operational objective requires it. Workloads can still override their own environment values through GitOps without changing Terraform.
