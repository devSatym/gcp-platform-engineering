#!/usr/bin/env python3
"""Validate repository-owned GitOps contracts before Argo CD consumes them."""

from __future__ import annotations

import json
from pathlib import Path
import sys

import yaml


ROOT = Path(__file__).resolve().parents[1]
GITOPS = ROOT / "gitops"
ENVIRONMENT = "dev"
EXPECTED_DASHBOARDS = {
    "platform-golden-signals",
    "platform-overview",
    "platform-telemetry-pipeline",
    "platform-logs-events",
    "platform-traces-service-graph",
}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_yaml(path: Path):
    try:
        with path.open(encoding="utf-8") as stream:
            return list(yaml.safe_load_all(stream))
    except yaml.YAMLError as exc:
        fail(f"invalid YAML in {path.relative_to(ROOT)}: {exc}")


def main() -> None:
    yaml_files = sorted([*GITOPS.rglob("*.yaml"), *GITOPS.rglob("*.yml")])
    for path in yaml_files:
        load_yaml(path)

    environment = load_yaml(GITOPS / "environments" / ENVIRONMENT / "config.yaml")[0]["environment"]
    wi_config = environment.get("workloadIdentity", {})

    for contract in sorted(GITOPS.glob("*/component.yaml")):
        component = load_yaml(contract)[0].get("component", {})
        name = component.get("name")
        source = component.get("source", {})
        values_path = component.get("values")
        if not all([name, component.get("namespace"), source.get("repoURL"), source.get("chart"), source.get("targetRevision"), values_path]):
            fail(f"incomplete component contract: {contract.relative_to(ROOT)}")
        if not (ROOT / values_path).is_file():
            fail(f"component values file is missing: {values_path}")
        for parameter in component.get("helmParameters", []):
            required_key = parameter.get("environmentValue")
            if not parameter.get("name") or not required_key or not wi_config.get(required_key):
                fail(f"component {name} has an unresolved environment Helm parameter")

    values = load_yaml(GITOPS / "kube-prometheus-stack" / "values.yaml")[0]
    grafana = values.get("grafana", {})
    provider = grafana.get("dashboardProviders", {}).get("dashboardproviders.yaml", {})
    providers = provider.get("providers", [])
    if not any(item.get("name") == "platform" and item.get("options", {}).get("path") == "/var/lib/grafana/dashboards/platform" for item in providers):
        fail("Grafana platform dashboard provider is missing or points at the wrong path")

    dashboards = grafana.get("dashboards", {}).get("platform", {})
    actual_uids = set()
    for name, dashboard in dashboards.items():
        raw_json = dashboard.get("json") if isinstance(dashboard, dict) else None
        if not raw_json:
            fail(f"Grafana dashboard {name} has no JSON payload")
        try:
            payload = json.loads(raw_json)
        except json.JSONDecodeError as exc:
            fail(f"Grafana dashboard {name} contains invalid JSON: {exc}")
        uid = payload.get("uid")
        if not uid:
            fail(f"Grafana dashboard {name} has no UID")
        actual_uids.add(uid)

    if actual_uids != EXPECTED_DASHBOARDS:
        fail(f"platform dashboard UIDs differ from the readiness contract: {sorted(actual_uids)}")

    readiness_job = (GITOPS / "bootstrap" / "observability-dashboard-readiness.yaml").read_text(encoding="utf-8")
    for uid in EXPECTED_DASHBOARDS:
        if uid not in readiness_job:
            fail(f"dashboard readiness hook does not verify {uid}")

    print(
        f"Validated {len(yaml_files)} GitOps YAML files, "
        f"{len(dashboards)} platform dashboards, and {len(list(GITOPS.glob('*/component.yaml')))} component contracts."
    )


if __name__ == "__main__":
    main()
