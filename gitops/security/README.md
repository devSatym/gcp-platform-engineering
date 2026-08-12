# Security platform domain

Reserved for GitOps-managed cluster security services and reusable policies.
Kyverno installation and policy enforcement will be added in a later change.
Policies must be workload-independent and environment-specific behavior must
come from `environments/*/config.yaml` or policy overlays.
