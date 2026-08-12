# =============================================================================
# modules/gke/logging.tf
#
# Defines the logging components exported to Cloud Logging.
# These locals are referenced in cluster.tf → logging_config block.
#
# Architecture:
#   GKE Node (system components + pod stdout/stderr)
#     │
#     ▼
#   Cloud Logging  ←── Operations (node health, API server audit, GKE events)
#     │
#     ▼                (Phase 8 addition)
#   Grafana Loki   ←── centralized log exploration with label-based filtering
#
# This dual approach mirrors production environments where platform teams need
# Cloud Logging for audit/compliance and Loki for developer log exploration.
# =============================================================================

locals {
  logging_components = [
    # SYSTEM_COMPONENTS: kube-system workloads, GKE system daemon logs,
    # kube-apiserver audit logs, scheduler, controller-manager.
    "SYSTEM_COMPONENTS",

    # WORKLOADS: pod stdout/stderr from all namespaces.
    # Each log line includes pod name, namespace, container name as labels
    # — making Cloud Logging the immediate operational log store.
    # Phase 8 will add Loki as a second log destination for richer querying.
    "WORKLOADS",
  ]
}
