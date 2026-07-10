# =============================================================================
# environments/dev/locals.tf
#
# TWO PURPOSES:
#   1. Common labels applied to all GCP resources in the dev environment.
#   2. PLATFORM SIZING — single source of truth for all resource sizes.
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  CHANGE RESOURCE SIZES HERE — nowhere else.                             │
# │  All module calls in main.tf read from local.sizing.*                   │
# │  This makes it trivial to resize the platform for different workloads.  │
# └─────────────────────────────────────────────────────────────────────────┘
# =============================================================================

locals {

  # ─── Common resource labels ───────────────────────────────────────────────
  labels = {
    environment = var.environment
    team        = "platform"
    project     = "otel-demo"
    managed-by  = "terraform"
    owner       = "satyam"
  }

  # ─── Platform Sizing ──────────────────────────────────────────────────────
  #
  # Philosophy:
  #   - system-pool  : Small, always-on. Runs ArgoCD, ESO, Prometheus, Falco.
  #                    e2-medium = 2vCPU / 4GB. Tight but fine for control plane.
  #
  #   - general-pool : Main workload pool. OTel Demo (20 svcs) + future
  #                    observability (Grafana, Loki) + chaos (LitmusChaos).
  #                    e2-standard-4 = 4vCPU / 16GB. Right-sized for Phase 5–11.
  #
  #   - spot-pool    : Interruptible only. Load generator, chaos runners.
  #                    Scales to 0 when idle. Use preemptible-tolerant workloads.
  #
  # Node count note:
  #   This is a REGIONAL cluster (asia-south1 = 3 zones).
  #   min_node_count is PER ZONE.
  #   min=1 → 3 nodes always running.  min=0 → pool can scale to 0.
  #
  # Cost reference (as of 2026, asia-south1):
  #   e2-medium      ≈ $0.034/hr per node  → 3 nodes ≈ $0.10/hr
  #   e2-standard-4  ≈ $0.134/hr per node  → 3 nodes ≈ $0.40/hr
  #   e2-standard-2  ≈ $0.067/hr per node  → 0 nodes (spot, idle) ≈ $0/hr
  #   Cluster mgmt   ≈ $0.10/hr (regional)
  #   Total running  ≈ $0.60/hr ≈ $14.40/day
  #   $300 credits   → ~20 full days of runtime
  #
  sizing = {

    # ── System Pool ───────────────────────────────────────────────────────
    # Hosts: ArgoCD, External Secrets Operator, metrics-server,
    #        Prometheus (Phase 8), Falco (Phase 7), OPA Gatekeeper (Phase 7)
    system_machine_type = "e2-medium"  # 2 vCPU / 4 GB
    system_disk_gb      = 50           # Standard OS + images for control plane tools
    system_min_count    = 1            # Per zone → 3 nodes always on (HA)
    system_max_count    = 2            # Per zone → 6 nodes max under pressure

    # ── General Pool ──────────────────────────────────────────────────────
    # Hosts: All OTel Demo microservices (20 services), Grafana, Loki,
    #        Jaeger, LitmusChaos (Phase 9), Istio sidecars (Phase 10)
    # Sizing rationale: 20 OTel svcs @ ~200m CPU / 256Mi each
    #   + observability stack ~1 CPU / 3GB
    #   + chaos runner ~0.5 CPU / 1GB
    #   Total per node needed: ~4 vCPU / 12GB → e2-standard-4 is the right fit
    general_machine_type = "e2-standard-4"  # 4 vCPU / 16 GB
    general_disk_gb      = 80              # Enough for all image layers (OTel images ~2-3GB each)
    general_min_count    = 1              # Per zone → 3 nodes always on
    general_max_count    = 3              # Per zone → 9 nodes max (handles load spikes)

    # ── Spot Pool ─────────────────────────────────────────────────────────
    # Hosts: OTel load generator, chaos experiments, non-critical batch jobs
    # Starts at 0 — only scales up when spot-tolerating workloads are deployed
    spot_machine_type = "e2-standard-2"  # 2 vCPU / 8 GB
    spot_disk_gb      = 50              # Standard — spot nodes pull images on demand
    spot_min_count    = 0              # Zero cost when idle
    spot_max_count    = 2              # Per zone → 6 nodes max

  }
}
