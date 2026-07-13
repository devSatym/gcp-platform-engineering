# Module: `gke`

> **Path:** `terraform/modules/gke/`  
> **Called from:** `environments/dev/main.tf` → `module "gke"`  
> **Phase:** 3 (GKE Cluster)

---

## Files

| File | Purpose |
|------|---------|
| `cluster.tf` | `google_container_cluster` — the GKE cluster resource |
| `nodepools.tf` | 3 node pools: system, general, spot |
| `workload_identity.tf` | Annotates node pool K8s SAs for Workload Identity |
| `autoscaling.tf` | `locals` for VPA and autoscaling config |
| `logging.tf` | `locals` for Cloud Logging component list |
| `monitoring.tf` | `locals` for Cloud Monitoring component list |
| `variables.tf` | All inputs (networking, sizing, SA emails, etc.) |
| `outputs.tf` | cluster_name, endpoint, CA cert, WI pool, node pool names |

---

## `cluster.tf` — `google_container_cluster "primary"`

The main GKE cluster resource. Uses `provider = google-beta` for beta features.

### Network attachment

```hcl
network    = var.vpc_name           # from module.networking
subnetwork = var.gke_subnet_name    # from module.networking

ip_allocation_policy {
  cluster_secondary_range_name  = var.gke_pods_range_name     # "gke-pods"
  services_secondary_range_name = var.gke_services_range_name  # "gke-services"
}
```

Both secondary range names come from `module.networking.outputs.tf` → `"gke-pods"` and `"gke-services"`.

---

### Private Cluster

```hcl
private_cluster_config {
  enable_private_nodes    = true              # Nodes have no public IPs
  enable_private_endpoint = var.enable_private_endpoint  # false in dev, true in prod
  master_ipv4_cidr_block  = var.master_ipv4_cidr_block   # Control plane CIDR
}

master_authorized_networks_config {
  cidr_blocks {
    cidr_block = var.master_authorized_cidr   # 0.0.0.0/0 in dev, VPN CIDR in prod
  }
}
```

Dev: public endpoint — `kubectl` works from local machine.  
Prod: `enable_private_endpoint = true`, restrict `master_authorized_cidr` to VPN/bastion.

---

### Kubernetes Version

```hcl
release_channel { channel = "REGULAR" }
```

`REGULAR` channel: GKE handles patch upgrades; minor upgrades are predictable.

---

### Dataplane V2 (eBPF)

```hcl
datapath_provider = "ADVANCED_DATAPATH"
```

Replaces kube-proxy + iptables with eBPF (Cilium-based).  
**Important:** With `ADVANCED_DATAPATH`, adding an explicit `network_policy {}` block causes **GKE API error 400**. Network policies are handled by Dataplane V2 automatically.

---

### Workload Identity

```hcl
workload_identity_config {
  workload_pool = "${var.project_id}.svc.id.goog"
}

node_config {
  service_account = var.gke_node_sa_email    # sa-gke-nodes
  workload_metadata_config {
    mode = "GKE_METADATA"   # Enables WI on nodes, blocks legacy metadata APIs
  }
}
```

`workload_pool = "{project}.svc.id.goog"` — this identity pool is referenced by the WI IAM bindings in `argocd-bootstrap/main.tf`.  
**CRITICAL:** The identity pool only exists **after** the cluster is created. This is why `module.argocd_bootstrap` has `depends_on = [module.gke]`.

---

### Other Key Features

| Feature | Config | Why |
|---------|--------|-----|
| Shielded Nodes | `enable_shielded_nodes = true` | Secure Boot + vTPM + Integrity Monitoring |
| Binary Authorization | `evaluation_mode = "DISABLED"` | Enabled in Phase 7 (Cosign signing) |
| Gateway API | `gateway_api_config { channel = "CHANNEL_STANDARD" }` | Prerequisite for Istio Gateway (Phase 9) |
| VPA | `vertical_pod_autoscaling { enabled = local.enable_vpa }` | Recommends CPU/memory requests |
| Cloud DNS | `dns_config { cluster_dns = "CLOUD_DNS" }` | Lower latency, better scalability than kube-dns |
| GCS Fuse CSI | `gcs_fuse_csi_driver_config { enabled = true }` | Mount Cloud Storage as volumes |
| Default pool removal | `remove_default_node_pool = true` | We manage our own pools in nodepools.tf |
| Deletion protection | `deletion_protection = false` | Allows terraform destroy (portfolio) |

---

### Lifecycle

```hcl
lifecycle {
  ignore_changes = [node_config, min_master_version]
}
```

Prevents replacement if GKE auto-upgrades change `min_master_version`.

---

### Depends On

```hcl
depends_on = [var.depends_on_nat]
```

`depends_on_nat = module.nat.nat_name` is passed in from `main.tf`. This is a workaround: Terraform doesn't support `depends_on` on module inputs, so the NAT name is passed as a variable to create an implicit dependency. GKE nodes need NAT to pull images before cluster creation completes.

---

## `nodepools.tf` — 3 Node Pools

### System Pool (`google_container_node_pool "system"`)

- **Machine:** From `var.system_pool_machine_type` → `local.sizing.system_machine_type` → `e2-medium`
- **Taint:** `workload=system:NoSchedule` — only system pods (ArgoCD, ESO, Prometheus, Falco) tolerate this
- **Node Label:** `workload: system`
- **Min:** `var.system_pool_min_count` (1/zone → 3 nodes)
- **Max:** `var.system_pool_max_count` (2/zone → 6 nodes)

### General Pool (`google_container_node_pool "general"`)

- **Machine:** `e2-standard-4` (4vCPU/16GB)
- **Taint:** `workload=general:NoSchedule`
- **Node Label:** `workload: general`
- **Hosts:** 20 OTel Demo services, Grafana, Loki, Jaeger
- **Min:** 1/zone → 3 nodes; **Max:** 3/zone → 9 nodes

### Spot Pool (`google_container_node_pool "spot"`)

- **Machine:** `e2-standard-2`
- **Taint:** `workload=spot:NoSchedule`
- **Spot/Preemptible:** enabled → significantly cheaper, can be evicted
- **Min:** 0/zone → scales to 0 when idle (zero cost)
- **Max:** 2/zone → 6 nodes
- **Hosts:** Load generator, chaos runners, non-critical batch jobs

All pools use `service_account = var.gke_node_sa_email` and `workload_metadata_config { mode = "GKE_METADATA" }`.

---

## `workload_identity.tf`

```hcl
# Annotates the node-level Kubernetes SA if needed.
# The actual pod-level WI bindings are in argocd-bootstrap/main.tf.
```

This file wires `argocd_sa_email` and `external_secrets_sa_email` into the cluster so they can be used in WI bindings created in the argocd-bootstrap module.

---

## `logging.tf` and `monitoring.tf`

These files define `locals` that feed into `cluster.tf`:

```hcl
# logging.tf
locals {
  logging_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

# monitoring.tf
locals {
  monitoring_components      = ["SYSTEM_COMPONENTS", "POD", "DAEMONSET", "DEPLOYMENT", "STATEFULSET"]
  enable_managed_prometheus  = true
}
```

`managed_prometheus { enabled = true }` enables GCP-managed Prometheus scraping alongside in-cluster Prometheus (Phase 8).

---

## `autoscaling.tf`

```hcl
locals {
  enable_vpa = true
}
```

Feeds into `vertical_pod_autoscaling { enabled = local.enable_vpa }` in `cluster.tf`.

---

## `outputs.tf` — What Gets Exported and Where It Goes

| Output | Value | Consumed By |
|--------|-------|-------------|
| `cluster_name` | `google_container_cluster.primary.name` | `module.argocd_bootstrap`, `outputs.tf`, GitHub Actions |
| `cluster_id` | `.id` | Informational |
| `cluster_self_link` | `.self_link` | Informational |
| `cluster_location` | `.location` | `module.argocd_bootstrap.cluster_region` |
| `cluster_endpoint` | `.endpoint` (sensitive) | `module.argocd_bootstrap`, `versions.tf` helm provider |
| `cluster_ca_certificate` | `.master_auth[0].cluster_ca_certificate` (sensitive) | `module.argocd_bootstrap`, `versions.tf` helm provider |
| `cluster_master_version` | `.master_version` | Verification |
| `workload_identity_pool` | `"{project}.svc.id.goog"` | `environments/dev/outputs.tf` |
| `system_pool_name` | node pool name | Verification |
| `general_pool_name` | node pool name | Verification |
| `spot_pool_name` | node pool name | Verification |
| `get_credentials_command` | gcloud command string | `outputs.tf` → printed after apply |
