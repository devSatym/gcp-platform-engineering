# ADR-001: Use Google Kubernetes Engine (GKE Standard) as the Kubernetes Platform

**Status:** `Accepted`

**Date:** 2026-07-09

**Author:** Satyam Agnihotri

---

## Context

We need a managed Kubernetes platform to run the OpenTelemetry Demo and all supporting platform components. The platform must support private networking, advanced security features, deep GCP integrations, and production-grade operations — while keeping management overhead reasonable for a platform engineering project.

Key requirements:
- Managed control plane (no self-managed etcd, API servers)
- Deep GCP service integration (Workload Identity, Cloud Logging, Cloud Monitoring)
- Support for private clusters with no public node IPs
- Advanced networking capabilities (VPC-native, eBPF dataplane)
- Multi-node-pool support for workload isolation
- Active community and enterprise production usage
- Upgrade automation

---

## Decision

Use **GKE Standard** (not Autopilot) in a **private, regional configuration** (`asia-south1`) on Google Cloud Platform.

---

## Rationale

GKE Standard was chosen because:

1. **GCP-native integrations are best-in-class:** Workload Identity, Cloud Logging, Cloud Monitoring, Binary Authorization, Dataplane V2, and Backup for GKE are first-party, deeply integrated features — not add-ons requiring third-party configuration.
2. **Standard over Autopilot:** Standard mode gives full control over node pool configuration, node labels/taints, machine types, preemptible/spot nodes, and autoscaling behavior. Autopilot is simpler but restricts the platform engineering concepts we want to demonstrate (custom node pools, spot pool, GPU pool planning, etc.).
3. **Private cluster from day one:** GKE Standard supports private nodes and private control plane with authorized networks — this is required for our security posture.
4. **Dataplane V2 (eBPF):** Only GKE Standard gives fine-grained control over enabling Dataplane V2, which provides better observability and network policy enforcement.
5. **Broad real-world usage:** GKE is widely used in production by many large organizations, making this project resume-relevant.

---

## Consequences

### Positive
- Full GCP ecosystem integration (Workload Identity, Binary Authorization, GKE Autopilot-level automation is optional)
- Dataplane V2 eBPF networking available
- Multi-node-pool support for system / general / spot workload separation
- First-party managed upgrades via release channels

### Negative / Trade-offs
- GCP lock-in for cluster management layer (node pool APIs, Workload Identity binding)
- GKE Standard requires more networking setup than Autopilot (VPC-native, secondary ranges, Cloud NAT)
- Standard clusters cost more than Autopilot for low-utilization scenarios (node VMs billed even when idle)

### Neutral
- GKE Standard clusters are VMs — standard Kubernetes `kubectl`, Helm, ArgoCD all work as expected

---

## Alternatives Considered

| Alternative | Reason Not Chosen |
|---|---|
| **GKE Autopilot** | Less control over node pools, machine types, spot configuration, taints. Would prevent demonstrating key platform engineering concepts. |
| **Amazon EKS** | Not GCP. The project is designed specifically as a GCP platform engineering showcase. |
| **Azure AKS** | Same reason as EKS. |
| **Self-managed Kubernetes (kubeadm)** | Unacceptable operational overhead. We want to focus on platform engineering above the cluster management layer. |
| **k3s / Kind** | Not suitable for production-grade GCP platform engineering demonstration. |

---

## References

- [GKE Standard vs Autopilot comparison](https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison)
- [GKE private clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/private-cluster-concept)
- [GKE Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2)
