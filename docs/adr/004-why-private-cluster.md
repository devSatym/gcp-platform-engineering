# ADR-004: Use a Private GKE Cluster from Day One

**Status:** `Accepted`

**Date:** 2026-07-09

**Author:** Satyam Agnihotri

---

## Context

When creating a GKE cluster, the fundamental networking choice is whether to use:
- A **public cluster** — nodes have public IP addresses, control plane is publicly accessible
- A **private cluster** — nodes have only private IP addresses, control plane accessible via VPC or authorized networks

This decision has significant downstream consequences. It affects the VPC design, NAT configuration, GitHub Actions connectivity, ArgoCD access, Ingress architecture, and the overall security posture.

Many tutorials and portfolio projects start with a public cluster and attempt to harden it later. We are making the opposite choice.

---

## Decision

Create a **private GKE cluster from day one**:
- Nodes have **no public IP addresses**
- Control plane accessible only via **private endpoint** within the VPC
- **Authorized networks** configured for access from specific CIDR ranges (e.g., Cloud Shell, VPN)
- Outbound internet access via **Cloud NAT** (not direct node public IPs)

---

## Rationale

1. **Security by design:** Starting private and opening up is much easier than starting public and locking down. A public cluster's node IPs are directly reachable from the internet — a significant attack surface.
2. **Production standard:** The vast majority of production GKE environments use private clusters. Starting with this design makes the project more representative of real-world platform engineering.
3. **Forces correct networking:** Building private from day one requires correctly designing VPC-native networking, Cloud NAT, secondary IP ranges, and authorized networks — all of which are skills interviewers look for.
4. **Downstream architecture consistency:** Private clusters naturally lead to Private Google Access (nodes can reach Google APIs without public IPs), Workload Identity (no need for external key distribution), and controlled egress — all features we want to demonstrate.
5. **Avoids retrofitting:** If we started with a public cluster and later tried to convert it to private, we'd need to recreate the cluster (GKE doesn't support converting in-place). Building private from the start avoids this painful rebuild.

---

## Consequences

### Positive
- Smaller attack surface (no public node IPs)
- Complies with most enterprise security baselines
- Forces correct understanding of Cloud NAT, Private Google Access, VPC-native networking
- Easier compliance auditing

### Negative / Trade-offs
- More complex initial networking setup (VPC-native, secondary ranges, Cloud NAT, authorized networks)
- GitHub Actions cannot reach the private GKE API server directly — requires using a Workload Identity Federation approach or a bastion/cloud build trigger
- ArgoCD's initial bootstrap requires access to the private API server — handled through Cloud Shell or IAP tunnel
- Slightly more complex `kubeconfig` generation

### Neutral
- All workloads inside the cluster function identically regardless of whether the cluster is public or private
- `kubectl` commands work via `gcloud container clusters get-credentials` with private endpoint flag

---

## Alternatives Considered

| Alternative | Reason Not Chosen |
|---|---|
| **Public cluster, harden later** | Common in tutorials, but represents technical debt. Requires cluster recreation to go private. The initial design should reflect production standards. |
| **Public cluster with firewall restrictions** | Firewall rules don't protect the GKE API server endpoint — it remains publicly accessible. Not equivalent to a private cluster. |
| **Autopilot (implicitly private)** | Autopilot is an option, but we chose GKE Standard (ADR-001) for control over node pools. GKE Standard private clusters are fully supported. |

---

## Implementation Notes

- Cloud NAT must be provisioned before GKE cluster creation — private nodes need outbound internet for pulling images during initial bootstrap
- Authorized networks should include: your Cloud Shell session IP (temporary), IAP proxy ranges
- `enable_private_nodes = true` and `enable_private_endpoint = false` initially (private nodes, but public control plane endpoint for easier access during development). Can move to fully private later.
- GitHub Actions will use **Workload Identity Federation** to authenticate to GCP — no need for the runner to directly reach the GKE API server during CI (ArgoCD handles deployments via GitOps)

---

## References

- [GKE Private Cluster Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/private-cluster-concept)
- [Private Cluster Best Practices](https://cloud.google.com/kubernetes-engine/docs/how-to/private-cluster-setup)
- [Cloud NAT Overview](https://cloud.google.com/nat/docs/overview)
- [Authorized Networks](https://cloud.google.com/kubernetes-engine/docs/how-to/authorized-networks)
