# =============================================================================
# modules/gke/workload_identity.tf
#
# NOTE: The Workload Identity IAM bindings for ArgoCD and External Secrets
# are managed exclusively in the argocd-bootstrap module
# (modules/argocd-bootstrap/main.tf) to avoid duplicate resource declarations.
#
# Previously, bindings were defined here AND in argocd-bootstrap/main.tf.
# The duplicate was removed from this file. The argocd-bootstrap module is
# the canonical location because it owns all ArgoCD/ESO-related IAM.
# =============================================================================
