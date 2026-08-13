# Reusable GCP DevSecOps Platform

> A production-style, reusable GCP platform for arbitrary Helm-based microservice workloads.

---

## Overview

This repository demonstrates how a mature platform engineering team would build, operate, and maintain a cloud-native platform on GCP — not just deploy an application.

This repository does not include a bundled application. Workloads are onboarded through the generic GitOps contract under `gitops/workloads/`. The platform owns:
- Terraform infrastructure
- Kubernetes platform (GKE)
- GitOps delivery (ArgoCD)
- CI/CD pipelines (GitHub Actions)
- Security enforcement (Kyverno, Binary Authorization)
- Observability (Prometheus, Grafana, Loki, Jaeger, telemetry collector)
- Service mesh (Istio)
- Progressive delivery (Argo Rollouts)
- Autoscaling & capacity engineering
- Chaos engineering (Chaos Mesh)
- SRE operations (SLOs, error budgets, runbooks)

---

## System Architecture

```
Developer
    │
    ▼
GitHub
    │
    ▼
GitHub Actions (CI — Build, Scan, Sign, Push)
    │
    ▼
Artifact Registry
    │
    ▼
Terraform (Cloud Infrastructure)
    │
    ▼
GCP / GKE (Kubernetes Platform)
    │
    ▼
ArgoCD (GitOps — Cluster State from Git)
    │
    ▼
Generic Helm Workload
    │
    ▼
Telemetry Collector → Prometheus → Grafana
                           → Cloud Monitoring
                           → Cloud Monitoring
    │
    ▼
SRE (SLOs, Runbooks, Incident Management)
```

---

## GCP Services Used

| Category | GCP Service |
|---|---|
| Kubernetes | GKE (Standard, Private, Regional) |
| Registry | Artifact Registry |
| DNS | Cloud DNS |
| SSL | Google Managed Certificates |
| Load Balancer | External HTTP(S) Load Balancer |
| Secrets | Secret Manager |
| IAM | Workload Identity |
| Storage | Cloud Storage (Terraform state, backups) |
| Monitoring | Cloud Monitoring |
| Logging | Cloud Logging |
| Traces | Cloud Trace (alongside Jaeger) |
| Metrics | Managed Prometheus (alongside OSS Prometheus) |
| Networking | VPC, Subnets, Firewall Rules |
| NAT | Cloud NAT |
| CI Authentication | Workload Identity Federation |
| Backup | Backup for GKE |

---

## Repository Structure

```
platform-engineering-gcp/
│
├── docs/                    # Architecture, ADRs, runbooks, design decisions
│   ├── architecture/        # Multi-level architecture diagrams
│   ├── adr/                 # Architecture Decision Records
│   ├── design/              # Platform principles, naming, IP addressing
│   ├── runbooks/            # Operational runbooks
│   ├── diagrams/            # Source diagrams (draw.io, etc.)
│   ├── operations/          # Day-2 operations guides
│   ├── onboarding/          # Developer onboarding
│   └── roadmap/             # Project roadmap
│
├── terraform/               # All GCP infrastructure as code
│   ├── modules/             # Reusable Terraform modules
│   └── environments/        # Per-environment Terraform configurations
│
├── bootstrap/               # One-time cluster bootstrap scripts
│
├── gitops/                  # ArgoCD applications, App of Apps, ApplicationSets
│   ├── bootstrap/           # Initial ArgoCD bootstrap
│   ├── projects/            # ArgoCD Projects (RBAC isolation)
│   ├── applications/        # ArgoCD Application manifests
│   ├── environments/        # Per-environment Helm values
│   ├── platform/            # Platform components (cert-manager, etc.)
│   ├── networking/          # Networking components (Istio, Gateway)
│   ├── observability/       # Observability stack (Prometheus, Grafana, Loki)
│   ├── security/            # Security policies (Kyverno, OPA)
│   └── tenants/             # Tenant-specific configurations
│
├── helm/                    # Custom Helm charts and value overrides
│
├── monitoring/              # Grafana dashboards, alert rules, SLO configs
│
├── security/                # Security policies, scanning configs, SBOM tooling
│
├── networking/              # Network policies, Istio configs
│
├── sre/                     # SLOs, error budget policies, runbooks
│
├── chaos/                   # Chaos Mesh experiments
│
├── scripts/                 # Utility scripts
│
├── .github/                 # GitHub Actions workflows
│   └── workflows/
│
└── gitops/workloads/       # Workload registrations and values
```

---

## Phase Roadmap

| # | Phase | Key Deliverables | Status |
|---|---|---|---|
| 1 | **Project Foundation & Architecture** | Repo layout, docs skeleton, ADRs, architecture diagrams, naming conventions | ✅ In Progress |
| 2 | **GCP Foundation & Network Architecture** | VPC, subnets, Cloud Router/NAT, firewall, remote Terraform state | ⬜ Not Started |
| 3 | **Production-Grade GKE Platform** | Private regional GKE, node pools, Workload Identity, Dataplane V2 | ⬜ Not Started |
| 4 | **GitOps Platform Bootstrap** | ArgoCD, App of Apps, ApplicationSets, sync waves, multi-env layout | ⬜ Not Started |
| 5 | **Deploy and validate example workloads** | Helm overlays, Artifact Registry, tiered scheduling, GCP ingress + TLS | ⬜ Not Started |
| 6 | **Enterprise CI/CD & Supply Chain** | GitHub Actions, image scanning (Trivy), signing (Cosign), SBOM | ⬜ Not Started |
| 7 | **Enterprise Security Platform** | Kyverno policies, Binary Authorization, OPA Gatekeeper, network policies | ⬜ Not Started |
| 8 | **Enterprise Observability Platform** | Custom Grafana dashboards, Loki, alerting, SLI metrics, telemetry collector tuning | ⬜ Not Started |
| 9 | **Service Mesh & Zero-Trust Networking** | Istio on GKE, mTLS, traffic management, PeerAuthentication | ⬜ Not Started |
| 10 | **Progressive Delivery** | Argo Rollouts, canary/blue-green deployments, automated verification | ⬜ Not Started |
| 11 | **Autoscaling & Capacity Engineering** | HPA, VPA, KEDA, cluster autoscaler tuning, load testing | ⬜ Not Started |
| 12 | **Chaos Engineering & Resilience** | Chaos Mesh experiments, fault injection, resilience runbooks | ⬜ Not Started |
| 13 | **SRE, Operations & Incident Management** | SLOs, error budgets, runbooks, on-call procedures | ⬜ Not Started |
| 14 | **Disaster Recovery & Backup** | Backup for GKE, DR strategy, RTO/RPO targets, restore testing | ⬜ Not Started |
| 15 | **FinOps & Cost Engineering** | Cost dashboards, spot optimization, rightsizing, recommendations | ⬜ Not Started |
| 16 | **Multi-Cluster & Fleet Management** | Multi-env promotion, cluster fleet management, GitOps at scale | ⬜ Not Started |
| 17 | **Production Readiness & Governance** | Readiness checklists, Day-2 operations, platform governance | ⬜ Not Started |
| 18 | **Portfolio & Documentation** | README polish, architecture diagrams, open source excellence | ⬜ Not Started |

---

## Architecture Principles

Every decision in this project follows these guiding principles:

1. **Infrastructure as Code only** — No manual console changes after initial setup. Everything is version-controlled and reproducible.
2. **GitOps-first** — Kubernetes state comes from Git. ArgoCD continuously reconciles the cluster against the desired state.
3. **Immutable deployments** — Images are never modified in place. Every deployment uses a new, tagged, immutable image.
4. **Least privilege** — IAM permissions are narrowly scoped. Workload Identity replaces long-lived service account keys.
5. **Managed services where practical** — GCP-managed offerings (GKE, Artifact Registry, Cloud DNS) reduce operational burden.
6. **Observability by default** — Every component exposes metrics, logs, and traces. No component ships without observability.
7. **Security built in** — Scanning, signing, and policy enforcement are part of the delivery pipeline, not afterthoughts.

---

## Getting Started

> 📖 See [the dev bootstrap guide](docs/DEV_BOOTSTRAP.md) for the current end-to-end deployment flow.

**Prerequisites:**
- GCP account with billing enabled
- `gcloud` CLI installed and authenticated
- `terraform` >= 1.5 installed
- `kubectl` installed
- `helm` >= 3.12 installed
- GitHub account

**Quick orientation:**
1. Read [docs/architecture/system-context.md](docs/architecture/system-context.md) — understand the big picture
2. Read [docs/design/platform-principles.md](docs/design/platform-principles.md) — understand our decisions
3. Review [docs/adr/](docs/adr/) — understand *why* we made key choices
4. Start with Phase 2 once Phase 1 is complete

---

## License

This project is licensed under the [Apache 2.0 License](LICENSE).


---
