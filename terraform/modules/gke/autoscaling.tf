# =============================================================================
# modules/gke/autoscaling.tf
#
# Defines autoscaling settings referenced by cluster.tf.
#
# Autoscaling strategy for this platform:
#
#   Cluster Autoscaler  → Scales node count per pool (configured in nodepools.tf)
#   VPA                 → Recommends optimal CPU/memory requests per container
#   HPA                 → Scales pod replicas based on CPU/memory/custom metrics
#                         (configured in Phase 11 alongside application)
#   KEDA                → Event-driven autoscaling for queue-based workloads
#                         (introduced in Phase 11)
#
# Phase 3 enables: VPA (recommendation mode only) + Cluster Autoscaler.
# Phase 11 configures: HPA policies per service + KEDA.
# =============================================================================

locals {
  # Enable Vertical Pod Autoscaler at cluster level.
  # VPA operates in RECOMMENDATION mode initially — it analyzes actual usage
  # and suggests CPU/memory request values without automatically applying them.
  # Phase 11 can switch specific workloads to AUTO mode for actual resizing.
  enable_vpa = true
}
