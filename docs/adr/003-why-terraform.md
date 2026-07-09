# ADR-003: Use Terraform for GCP Infrastructure as Code

**Status:** `Accepted`

**Date:** 2026-07-09

**Author:** Satyam Agnihotri

---

## Context

We need an Infrastructure as Code (IaC) tool to provision and manage all GCP resources: VPC, subnets, Cloud Router, Cloud NAT, firewall rules, service accounts, GKE cluster, Artifact Registry, Cloud DNS, and related IAM bindings. The tool must support:
- Modular, reusable code structure
- Remote state management
- Plan/apply workflow for change review before deployment
- GCP provider with broad resource coverage
- Team familiarity and industry adoption

---

## Decision

Use **Terraform** (>= 1.5) with the `hashicorp/google` and `hashicorp/google-beta` providers, organized into reusable modules under `terraform/modules/` and per-environment configurations under `terraform/environments/`.

---

## Rationale

1. **Industry standard:** Terraform is the most widely used IaC tool in the cloud engineering space. It appears in the vast majority of DevOps/Platform Engineering job descriptions.
2. **Mature GCP provider:** The `hashicorp/google` provider has comprehensive GCP resource coverage, is maintained jointly by HashiCorp and Google, and is considered the production standard for GCP IaC.
3. **Module system:** Terraform modules enable a clean separation between reusable resource patterns (the `modules/` directory) and environment-specific configurations (the `environments/` directory).
4. **Plan/apply workflow:** The `terraform plan` output allows reviewing infrastructure changes before applying — essential for production environments and valuable for code review processes.
5. **Remote state:** GCS backend for Terraform state enables team collaboration, state locking, and versioned history.
6. **Ecosystem:** Extensive community modules (`terraform-google-modules`), tooling (`tflint`, `checkov`, `terraform-docs`), and CI/CD integrations.

---

## Consequences

### Positive
- Reproducible, version-controlled infrastructure
- `terraform plan` gives a clear diff before every change
- Modular structure scales to multi-project, multi-region deployments
- Compatible with `checkov` (policy scanning), `tflint` (linting), `terraform-docs` (documentation generation)

### Negative / Trade-offs
- State file management complexity — must keep state secure and handle drift carefully
- Terraform is declarative but not always idempotent for complex ordering scenarios
- `google-beta` provider sometimes needed for new GKE features — version management required
- Terraform itself has GCP-specific knowledge gaps (some newer GKE APIs lag behind)

### Neutral
- All Kubernetes resources (ArgoCD Applications, Helm releases) are managed by ArgoCD — Terraform only manages GCP cloud resources

---

## Alternatives Considered

| Alternative | Reason Not Chosen |
|---|---|
| **Pulumi** | Better for teams comfortable with general-purpose languages (Python, TypeScript). Less ecosystem adoption than Terraform for GCP. Portfolio projects using Terraform are more recognizable to interviewers. |
| **Crossplane** | Kubernetes-native IaC. Excellent for advanced platform engineering but adds significant complexity for initial infrastructure provisioning. Better suited as a future enhancement. |
| **Google Cloud Deployment Manager** | GCP-proprietary, limited community support, less flexible than Terraform. |
| **gcloud CLI scripts** | Not declarative, hard to review changes, difficult to track state, poor collaboration model. |
| **Ansible** | Configuration management tool, not designed for cloud resource provisioning. |

---

## References

- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [terraform-google-modules](https://github.com/terraform-google-modules)
- [GCS Terraform backend](https://developer.hashicorp.com/terraform/language/settings/backends/gcs)
- [checkov](https://www.checkov.io/)
- [tflint](https://github.com/terraform-linters/tflint)
