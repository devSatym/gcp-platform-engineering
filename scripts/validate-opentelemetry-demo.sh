#!/usr/bin/env bash
# Render and assert the dev OpenTelemetry Demo contract without changing a
# cluster. Runtime telemetry validation remains a separate, live-environment
# step because metric names and labels must be observed rather than assumed.

set -Eeuo pipefail

readonly CHART_REPOSITORY="https://open-telemetry.github.io/opentelemetry-helm-charts"
readonly CHART_VERSION="0.40.9"
readonly RELEASE_NAME="opentelemetry-demo"
readonly WORKLOAD_NAMESPACE="opentelemetry-demo-dev"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered_manifest="$(mktemp -t opentelemetry-demo-dev.XXXXXX.yaml)"
trap 'rm -f -- "${rendered_manifest}"' EXIT

command -v helm >/dev/null 2>&1 || {
  printf 'Error: helm must be installed.\n' >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  printf 'Error: python3 must be installed.\n' >&2
  exit 1
}

helm template "${RELEASE_NAME}" opentelemetry-demo \
  --repo "${CHART_REPOSITORY}" \
  --version "${CHART_VERSION}" \
  --namespace "${WORKLOAD_NAMESPACE}" \
  --values "${repo_root}/gitops/workloads/opentelemetry-demo/values/base.yaml" \
  --values "${repo_root}/gitops/workloads/opentelemetry-demo/values/dev.yaml" \
  >"${rendered_manifest}"

python3 - "${rendered_manifest}" <<'PY'
from __future__ import annotations

from pathlib import Path
import sys

import yaml


manifest_path = Path(sys.argv[1])
documents = [document for document in yaml.safe_load_all(manifest_path.read_text()) if isinstance(document, dict)]
deployments = {
    document["metadata"]["name"]: document
    for document in documents
    if document.get("kind") == "Deployment"
}
services = {
    document["metadata"]["name"]: document
    for document in documents
    if document.get("kind") == "Service"
}

expected_deployments = {"flagd", "load-generator", "llm", "product-reviews"}
missing = expected_deployments.difference(deployments)
if missing:
    raise SystemExit(f"ERROR: expected dev Deployments are missing: {sorted(missing)}")

embedded_backends = {"otel-collector", "prometheus", "grafana", "jaeger", "opensearch"}
unexpected = embedded_backends.intersection(deployments)
if unexpected:
    raise SystemExit(f"ERROR: embedded observability Deployments must stay disabled: {sorted(unexpected)}")

load_generator = deployments["load-generator"]
containers = load_generator["spec"]["template"]["spec"]["containers"]
container = next((item for item in containers if item.get("name") == "load-generator"), None)
if container is None:
    raise SystemExit("ERROR: load-generator Deployment has no load-generator container")

environment = {item["name"]: item.get("value") for item in container.get("env", [])}
expected_environment = {
    "LOCUST_USERS": "50",
    "LOCUST_SPAWN_RATE": "5",
    "LOCUST_BROWSER_TRAFFIC_ENABLED": "false",
    "OTEL_RESOURCE_ATTRIBUTES": "deployment.environment.name=dev,service.namespace=opentelemetry-demo",
}
for name, expected in expected_environment.items():
    actual = environment.get(name)
    if actual != expected:
        raise SystemExit(f"ERROR: {name} is {actual!r}; expected {expected!r}")

resources = container.get("resources", {})
expected_resources = {
    "requests": {"cpu": "100m", "memory": "256Mi"},
    "limits": {"cpu": "500m", "memory": "1500Mi"},
}
if resources != expected_resources:
    raise SystemExit(f"ERROR: load-generator resources are {resources!r}; expected {expected_resources!r}")

pod_spec = load_generator["spec"]["template"]["spec"]
if pod_spec.get("nodeSelector") != {"workload": "general"}:
    raise SystemExit(
        "ERROR: dev load-generator must use general capacity when spot capacity is unavailable"
    )

spot_toleration = any(
    item.get("key") == "workload"
    and item.get("value") == "spot"
    and item.get("effect") == "NoSchedule"
    for item in pod_spec.get("tolerations", [])
)
if spot_toleration:
    raise SystemExit("ERROR: dev load-generator must not tolerate the spot-node taint")

frontend_proxy = services.get("frontend-proxy")
if frontend_proxy is None:
    raise SystemExit("ERROR: frontend-proxy Service is required for the flagd-ui helper")

frontend_proxy_ports = {
    port.get("port")
    for port in frontend_proxy.get("spec", {}).get("ports", [])
}
if 8080 not in frontend_proxy_ports:
    raise SystemExit(
        "ERROR: frontend-proxy Service must expose port 8080 for the flagd-ui helper"
    )

print(
    "Validated OpenTelemetry Demo dev render: "
    "complete Locust route dependencies, 50 users at 5 users/s, HTTP-only traffic, "
    "payment-failure prerequisites, and no embedded observability backends."
)
PY
