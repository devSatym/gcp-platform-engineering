Using the architecture defined in docs/REUSABILITY_AUDIT.md, create a repository-root AGENTS.md.

The AGENTS.md must permanently instruct future coding agents that this is a reusable DevSecOps platform rather than an generic workload deployment platform.

Include rules for:

Terraform:

reusable modules
typed variables
variable validation
outputs
no environment-specific constants
provider version constraints
terraform fmt
terraform validate
optional tflint support

Kubernetes:

workload independence
securityContext
probes
resource limits
NetworkPolicies where appropriate
PodDisruptionBudgets where applicable
namespaces from configuration

Helm:

external charts should remain external where possible
values-based customization
workload charts remain workload-owned
platform charts/config remain platform-owned

ArgoCD:

GitOps is source of truth
ApplicationSets preferred for repeated environment/workload generation
no duplicated Applications unless justified
sync waves for dependencies
automated sync behavior must be intentional

Security:

least privilege
no credentials
no long-lived GCP service account keys
WIF preferred
Kyverno policies reusable
CI image/SBOM scanning
image signing support
production policy stricter than development where reasonable

Observability:

platform-level stack independent from workloads
workload integration based on standard metrics/logs/traces interfaces
standard telemetry conventions
dashboards must avoid hardcoded workload identity where possible

Safety:
Never automatically execute:

terraform apply
terraform destroy
kubectl delete
helm uninstall
gcloud project deletion
IAM destructive changes
git push --force

Working method:
inspect → plan → modify → validate → summarize