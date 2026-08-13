#!/usr/bin/env bash
# Expose platform and OpenTelemetry Demo web UIs through localhost-only
# kubectl port-forwards. This script never creates external load balancers,
# modifies cluster resources, or retrieves credentials.

set -Eeuo pipefail

readonly DEFAULT_ENVIRONMENT="dev"
readonly ARGOCD_NAMESPACE="argocd"
readonly OBSERVABILITY_NAMESPACE="observability"

environment="${DEFAULT_ENVIRONMENT}"
workload_namespace=""
kube_context=""

declare -a kubectl_cmd=(kubectl)
declare -a forward_pids=()
declare -a forward_logs=()
declare -a unavailable=()
started_forwards=0

usage() {
  cat <<'EOF'
Usage: scripts/expose-platform-uis.sh [options]

Expose the available Argo CD, OpenTelemetry Demo, and observability web UIs
using localhost-only kubectl port-forwards. Keep this command running while
using the UIs; press Ctrl-C to close every port-forward.

Options:
  -e, --environment NAME          Workload environment (default: dev).
  -n, --workload-namespace NAME  Override the OpenTelemetry Demo namespace.
  -c, --context NAME              Use this kubeconfig context.
  -h, --help                      Show this help text.

Default URLs when their backing Services are installed:
  Argo CD                         http://127.0.0.1:8080
  OpenTelemetry Demo              http://127.0.0.1:8081
  Platform Grafana                http://127.0.0.1:3000
  Platform Prometheus             http://127.0.0.1:9090
  Platform Alertmanager           http://127.0.0.1:9093

Loki, Tempo, and the OpenTelemetry Collector are backend services rather than
web dashboards. Query logs and traces through the shared Grafana Explore UI.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local exit_code=$?
  local pid

  trap - EXIT INT TERM

  if ((${#forward_pids[@]} > 0)); then
    printf '\nStopping localhost port-forwards...\n'
    for pid in "${forward_pids[@]}"; do
      kill "${pid}" 2>/dev/null || true
    done
    for pid in "${forward_pids[@]}"; do
      wait "${pid}" 2>/dev/null || true
    done
  fi

  if ((${#forward_logs[@]} > 0)); then
    rm -f -- "${forward_logs[@]}"
  fi

  exit "${exit_code}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while (($# > 0)); do
  case "$1" in
    -e|--environment)
      (($# >= 2)) || die "${1} requires an environment name."
      environment="$2"
      shift 2
      ;;
    -n|--workload-namespace)
      (($# >= 2)) || die "${1} requires a namespace."
      workload_namespace="$2"
      shift 2
      ;;
    -c|--context)
      (($# >= 2)) || die "${1} requires a kubeconfig context."
      kube_context="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

if [[ -z "${workload_namespace}" ]]; then
  workload_namespace="opentelemetry-demo-${environment}"
fi

command -v kubectl >/dev/null 2>&1 || die "kubectl must be installed and on PATH."

if [[ -n "${kube_context}" ]]; then
  kubectl_cmd+=(--context "${kube_context}")
fi

"${kubectl_cmd[@]}" version --request-timeout=10s >/dev/null 2>&1 || \
  die "Cannot reach the Kubernetes API. Authenticate to GKE or pass --context."

service_name() {
  local namespace="$1"
  shift

  local candidate
  for candidate in "$@"; do
    if "${kubectl_cmd[@]}" --namespace "${namespace}" get service "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

start_port_forward() {
  local id="$1"
  local display_name="$2"
  local namespace="$3"
  local local_port="$4"
  local remote_port="$5"
  local url="$6"
  shift 6

  local service
  if ! service="$(service_name "${namespace}" "$@")"; then
    unavailable+=("${display_name} (no supported Service found in namespace ${namespace})")
    return 0
  fi

  # Do this before starting kubectl. Without the preflight check, an existing
  # listener could make the readiness probe below appear successful even though
  # this port-forward failed to bind its requested local port.
  if (exec 3<>"/dev/tcp/127.0.0.1/${local_port}") 2>/dev/null; then
    unavailable+=("${display_name} (localhost port ${local_port} is already in use)")
    return 0
  fi

  local log_file
  log_file="$(mktemp -t "${id}.XXXXXX.log")"

  "${kubectl_cmd[@]}" --namespace "${namespace}" port-forward \
    --address 127.0.0.1 "service/${service}" "${local_port}:${remote_port}" \
    >"${log_file}" 2>&1 &
  local pid=$!

  local attempt
  # A private GKE API can take a few seconds to establish each tunnel.
  for ((attempt = 0; attempt < 300; attempt++)); do
    # kubectl buffers its redirected status output, so test the listener rather
    # than relying on its log line. The subshell closes the probe connection.
    if (exec 3<>"/dev/tcp/127.0.0.1/${local_port}") 2>/dev/null; then
      forward_pids+=("${pid}")
      forward_logs+=("${log_file}")
      ((started_forwards += 1))
      printf '  %-30s %s\n' "${display_name}" "${url}"
      return 0
    fi

    if ! kill -0 "${pid}" 2>/dev/null; then
      printf 'Warning: %s could not use localhost port %s.\n' "${display_name}" "${local_port}" >&2
      sed 's/^/  /' "${log_file}" >&2 || true
      rm -f -- "${log_file}"
      return 0
    fi

    sleep 0.1
  done

  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  printf 'Warning: %s did not become ready for port-forwarding.\n' "${display_name}" >&2
  sed 's/^/  /' "${log_file}" >&2 || true
  rm -f -- "${log_file}"
}

printf 'Opening available UIs for Kubernetes context: %s\n' \
  "$("${kubectl_cmd[@]}" config current-context 2>/dev/null || printf 'selected context')"
printf 'All listeners bind only to 127.0.0.1.\n\n'

start_port_forward \
  "argocd" "Argo CD" "${ARGOCD_NAMESPACE}" 8080 80 "http://127.0.0.1:8080" \
  "argocd-server"

start_port_forward \
  "otel-demo" "OpenTelemetry Demo" "${workload_namespace}" 8081 8080 "http://127.0.0.1:8081" \
  "frontend-proxy" \
  "opentelemetry-demo-frontendproxy" "otel-demo-frontendproxy" \
  "opentelemetry-demo-frontend-proxy" "otel-demo-frontend-proxy"

start_port_forward \
  "platform-grafana" "Platform Grafana" "${OBSERVABILITY_NAMESPACE}" 3000 80 "http://127.0.0.1:3000" \
  "kube-prometheus-stack-grafana"

start_port_forward \
  "platform-prometheus" "Platform Prometheus" "${OBSERVABILITY_NAMESPACE}" 9090 9090 "http://127.0.0.1:9090" \
  "kube-prometheus-stack-prometheus"

start_port_forward \
  "platform-alertmanager" "Platform Alertmanager" "${OBSERVABILITY_NAMESPACE}" 9093 9093 "http://127.0.0.1:9093" \
  "kube-prometheus-stack-alertmanager"

if ((${#unavailable[@]} > 0)); then
  printf '\nNot exposed yet (Argo CD may still be synchronizing):\n'
  printf '  - %s\n' "${unavailable[@]}"
fi

if ((started_forwards == 0)); then
  die "No supported UI Services are available in the selected cluster."
fi

printf '\nPort-forwards are active. Press Ctrl-C to stop them.\n'
while :; do
  sleep 60
done
