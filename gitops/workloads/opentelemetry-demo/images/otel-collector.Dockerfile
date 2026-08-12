# =============================================================================
# applications/otel-collector/Dockerfile
#
# Custom OpenTelemetry Collector with GCP exporter support.
#
# PHASE STATUS: Placeholder — Phase 6 activates image mirroring.
#
# WHY A CUSTOM COLLECTOR?
# The upstream OTel Demo ships with a standard otelcol-contrib image.
# This custom build will extend it with:
#   - googlecloud exporter (for Cloud Monitoring / Cloud Trace)
#   - googlemanagedprometheus exporter (for Managed Prometheus)
#   - Custom build metadata (commit SHA, build date)
#
# This Dockerfile is intentionally minimal for now.
# The full custom build will be added when:
#   1. Cloud Monitoring integration is configured (Phase 8)
#   2. The collector config in base.yaml enables the googlecloud exporter
#
# BUILD (manual, for testing):
#   docker build -t otel-collector-custom:local .
#
# IN CI (build.yaml):
#   Triggered automatically on changes to this directory.
#   Pushed to asia-south1-docker.pkg.dev/{project}/platform-docker/otel-collector-custom
# =============================================================================

# Pin the base image — never use 'latest'
# Check releases: https://github.com/open-telemetry/opentelemetry-collector-releases/releases
FROM otel/opentelemetry-collector-contrib:0.104.0

# Build-time metadata (injected by build.yaml via --build-arg)
ARG BUILD_VERSION="dev"
ARG BUILD_DATE=""
ARG VCS_REF=""

# OCI image labels for traceability
LABEL org.opencontainers.image.title="Custom OTel Collector" \
      org.opencontainers.image.description="Extended OTel Collector with GCP exporter support" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/YOUR_USERNAME/project-2"

# Security: the base image already runs as non-root (user 10001)
# Do not switch to root here

# Copy custom collector config (overrides the default in the Helm chart)
# This will be populated in Phase 8 when GCP exporters are enabled
# COPY collector-config.yaml /etc/otelcol-contrib/config.yaml

# Health check — collector exposes health on port 13133
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:13133/health || exit 1

# Ports:
#   4317  - OTLP gRPC receiver
#   4318  - OTLP HTTP receiver
#   8888  - Prometheus metrics (self-observability)
#   13133 - Health check extension
EXPOSE 4317 4318 8888 13133
