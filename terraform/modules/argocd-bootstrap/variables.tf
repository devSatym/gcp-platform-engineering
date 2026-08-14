# =============================================================================
# modules/argocd-bootstrap/variables.tf
# =============================================================================

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

# ─── GKE cluster (from Phase 3 gke module outputs) ───────────────────────────

variable "cluster_name" {
  description = "GKE cluster name. From gke module output."
  type        = string
}

variable "cluster_endpoint" {
  description = "GKE API server endpoint (IP). From gke module output."
  type        = string
  sensitive   = true
}

variable "cluster_location" {
  description = "GKE cluster location (region or zone). From gke module output."
  type        = string
}

variable "environment" {
  description = "GitOps environment name whose generated Applications must converge after bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.environment))
    error_message = "environment must be a lowercase DNS-style identifier."
  }
}

variable "gitops_ready_timeout_seconds" {
  description = "Maximum time Terraform waits for Argo CD to reconcile generated platform and workload Applications."
  type        = number
  default     = 1800

  validation {
    condition     = var.gitops_ready_timeout_seconds >= 300 && var.gitops_ready_timeout_seconds <= 3600
    error_message = "gitops_ready_timeout_seconds must be between 300 and 3600 seconds."
  }
}

# ─── Service accounts (from Phase 2 service-accounts module outputs) ──────────

variable "argocd_sa_email" {
  description = "GCP SA email for ArgoCD Workload Identity binding. From service_accounts module."
  type        = string
}

variable "external_secrets_sa_email" {
  description = "GCP SA email for External Secrets Operator Workload Identity binding."
  type        = string
}

# ─── ArgoCD configuration ─────────────────────────────────────────────────────

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version to install. Pin to a known stable version."
  type        = string
  default     = "10.3.3"
}

variable "git_repo_url" {
  description = "HTTPS URL of the Git monorepo ArgoCD will watch. Example: https://github.com/owner/repo.git"
  type        = string
  # No default — must be set explicitly in every environment's main.tf.
  # If not set, Terraform will error at plan time (safer than a bad default).
}
