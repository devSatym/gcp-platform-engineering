# =============================================================================
# modules/github-wif/variables.tf
# =============================================================================

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in 'owner/repo' format. Only this repository can authenticate. Example: 'satyam-agnihotri/project-2'"
  type        = string
}

variable "github_actions_sa_email" {
  description = "GCP SA email for GitHub Actions (sa-github-actions). Created in Phase 2 service-accounts module. WIF allows this SA to be impersonated by GitHub Actions."
  type        = string
}
