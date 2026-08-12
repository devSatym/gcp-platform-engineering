# Platform Environment Composition Module

This module composes the reusable GCP foundation modules for one independent
platform environment. It owns composition and dependency ordering only; the
underlying modules own individual GCP resources.

Environment roots should provide one structured `config` object. The object is
where project IDs, regions, CIDRs, cluster sizing, node pools, GKE settings,
Artifact Registry settings, GitHub WIF settings, labels, and bootstrap options
vary between environments.

This module does not manage normal Kubernetes workload resources. The
`argocd-bootstrap` child is only the Terraform-to-ArgoCD handoff; ArgoCD owns
the normal Kubernetes platform and workload state after bootstrap.
