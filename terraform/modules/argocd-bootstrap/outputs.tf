# =============================================================================
# modules/argocd-bootstrap/outputs.tf
# =============================================================================

output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed."
  value       = helm_release.argocd.namespace
}

output "argocd_chart_version" {
  description = "Installed ArgoCD Helm chart version."
  value       = helm_release.argocd.version
}

output "argocd_access_command" {
  description = "Command to access the ArgoCD UI locally via port-forward."
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "argocd_password_command" {
  description = "Command to retrieve the initial ArgoCD admin password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
}
