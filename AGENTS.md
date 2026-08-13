# DevSecOps platform contribution guide

This repository implements a reusable DevSecOps platform. It is not a generic
workload deployment repository, and platform code must not become coupled to a
specific application. Workloads own their charts, application code, values, and
workload-specific dashboards; the platform owns shared infrastructure, policy,
observability, and GitOps orchestration.

## Working method

Always follow: **inspect → plan → modify → validate → summarize**. Preserve
unrelated worktree changes and make the smallest cohesive change that resolves
the issue.

## Terraform

- Build reusable modules with typed input variables, descriptions, validation,
  and useful outputs.
- Keep environment-specific values in environment configuration; do not embed
  environment constants in reusable modules.
- Pin provider versions with compatible version constraints.
- Run `terraform fmt` and `terraform validate` for changed roots. Run TFLint
  when it is available and relevant.
- Terraform owns cloud infrastructure and the minimal Argo CD bootstrap only;
  ordinary Kubernetes workloads belong to GitOps.

## Kubernetes and Helm

- Keep workloads independent from platform implementation details.
- Workload manifests and charts must use configured namespaces, security
  contexts, probes, and resource requests and limits.
- Add NetworkPolicies where traffic boundaries warrant them and
  PodDisruptionBudgets where availability requirements and replica counts make
  them meaningful.
- Keep third-party charts external where possible and customize them through
  values.
- Workload charts and values remain workload-owned. Platform charts and shared
  configuration remain platform-owned.

## Argo CD and GitOps

- Git is the source of truth for Kubernetes resources.
- Prefer ApplicationSets for repeated workload or environment generation; do
  not duplicate Applications without a documented reason.
- Use sync waves for dependencies such as CRDs, operators, and consumers.
- Make automated sync, prune, and self-heal settings intentional and
  environment-appropriate.

## Security

- Apply least privilege and never commit credentials.
- Do not create or use long-lived GCP service-account keys; use Workload
  Identity Federation where possible.
- Keep Kyverno policies reusable and apply stricter production policy where
  practical.
- Preserve CI support for image scanning, SBOM generation, and image signing.

## Observability

- Keep the metrics, logs, traces, and dashboard stack platform-owned and
  workload-independent.
- Workloads integrate through standard metrics, logs, and OTLP interfaces and
  standard telemetry conventions.
- Do not hardcode workload identity in shared dashboards when a label- or
  variable-driven view can be used.

## Safety

Never automatically execute:

- `terraform apply` or `terraform destroy`
- `kubectl delete`
- `helm uninstall`
- GCP project deletion or destructive IAM changes
- `git push --force`
