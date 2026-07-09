# =============================================================================
# modules/gke/monitoring.tf
#
# Defines the monitoring components exported to Cloud Monitoring.
# These locals are referenced in cluster.tf → monitoring_config block.
#
# Observability strategy (dual stack):
#
#   Cloud Monitoring  ← Node, cluster, infrastructure metrics (GCP-native)
#   Prometheus        ← Application metrics, SLI/SLO metrics (Phase 8, in-cluster)
#
# Both serve different audiences and use cases:
#   Cloud Monitoring: SRE/ops team, PagerDuty alerting, GCP cost dashboards
#   Prometheus/Grafana: Developer dashboards, OTel business metrics, SLO tracking
#
# Managed Prometheus (enabled below) provides a GCP-hosted Prometheus scraping
# endpoint — this is optional/complementary, not a replacement for in-cluster
# Prometheus which gives richer configuration (recording rules, alertmanager).
# =============================================================================

locals {
  monitoring_components = [
    # SYSTEM_COMPONENTS: node CPU, memory, disk, network metrics.
    # Populates the default GKE dashboards in Cloud Monitoring.
    "SYSTEM_COMPONENTS",
  ]

  # Managed Prometheus: GKE automatically scrapes pod metrics and stores them
  # in a GCP-hosted Prometheus backend queryable via PromQL.
  # Phase 8 introduces in-cluster Prometheus for richer application metrics.
  enable_managed_prometheus = true
}
