# ADR-002: Use Argo CD as the GitOps Controller

**Status:** `Accepted`

**Date:** 2026-07-09

**Author:** Satyam Agnihotri

---

## Context

We need a GitOps controller to continuously reconcile the Kubernetes cluster state against the desired state stored in Git. The controller must support:
- Multi-environment deployments (dev, stage, prod)
- Helm chart management
- ApplicationSets for scalable multi-cluster/multi-env templating
- App of Apps pattern for hierarchical application management
- Sync waves for ordered deployment
- A rich UI for visualizing application state
- RBAC for role-based access to applications
- Health checks and drift detection

---

## Decision

Use **Argo CD** as the GitOps controller, installed via its official Helm chart in the `argocd` namespace.

---

## Rationale

1. **Industry-standard tool:** Argo CD is the most widely adopted GitOps controller in the Kubernetes ecosystem, making this project relevant to the majority of DevOps/Platform Engineering job openings.
2. **Rich UI:** Argo CD's web interface provides application topology visualization, sync status, resource health, and rollback — useful for demos and portfolio showcasing.
3. **ApplicationSets:** The ApplicationSet controller eliminates per-environment YAML duplication and enables scalable multi-cluster deployments with generators.
4. **App of Apps pattern:** Argo CD natively supports the App of Apps pattern, which is our bootstrap strategy for platform components.
5. **Argo CD Rollouts integration:** Later phases introduce Argo Rollouts for progressive delivery — having ArgoCD as the base makes this integration seamless.
6. **Notifications:** Built-in notification engine for Slack, email, webhooks — directly supports our SRE observability goals.
7. **RBAC:** First-class RBAC with project-based isolation.

---

## Consequences

### Positive
- Declarative GitOps with automatic reconciliation and self-healing
- App of Apps and ApplicationSets reduce boilerplate for multi-env management
- Beautiful UI simplifies portfolio demonstrations
- Native integration with Argo Rollouts (Phase 10)
- Webhook and notification support built in

### Negative / Trade-offs
- Argo CD is a significant addition to the platform — runs its own set of controllers, Redis, server, and application controller
- RBAC configuration is more complex than Flux
- The Argo CD server is a potential attack surface (must be secured properly in Phase 7)

### Neutral
- Argo CD watches the `gitops/` directory in our monorepo — any Git push triggers reconciliation

---

## Alternatives Considered

| Alternative | Reason Not Chosen |
|---|---|
| **Flux v2** | Excellent tool, but less UI visibility, no App of Apps pattern natively, fewer job postings mention Flux vs ArgoCD. |
| **Manual `kubectl apply`** | No audit trail, no reconciliation, no drift detection — anti-pattern for platform engineering. |
| **Terraform for Kubernetes resources** | Mixes cloud infrastructure (Terraform's domain) with Kubernetes resource lifecycle (ArgoCD's domain). Creates circular dependency issues. |
| **Jenkins X** | Heavier, less composable, less community adoption in 2024-2025. |

---

## References

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [ApplicationSet Controller](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Argo CD Notifications](https://argocd-notifications.readthedocs.io/)
