#!/usr/bin/env bash
# Validate a live OpenTelemetry Demo deployment and operate its selected,
# built-in payment failure through flagd-ui. This script never applies or
# deletes Kubernetes resources, and it always uses a localhost-only tunnel.

set -Eeuo pipefail

readonly DEFAULT_ENVIRONMENT="dev"
readonly OBSERVABILITY_NAMESPACE="observability"
readonly LOCAL_PORT="${OTEL_DEMO_FLAGD_LOCAL_PORT:-18080}"

environment="${DEFAULT_ENVIRONMENT}"
kube_context=""
state_file=""
declare -a kubectl_cmd=(kubectl)
forward_pid=""
forward_log=""
transient_file=""

usage() {
  cat <<'EOF'
Usage:
  scripts/otel-demo-observability.sh preflight [options]
  scripts/otel-demo-observability.sh payment-failure enable --state-file PATH [options]
  scripts/otel-demo-observability.sh payment-failure restore --state-file PATH [options]

Options:
  -e, --environment NAME  Workload environment (default: dev).
  -c, --context NAME      Kubernetes context to use.
  -s, --state-file PATH   Required flagd configuration backup file.
  -h, --help              Show this help text.

The enable command reads the complete flagd configuration, writes it to the
state file with mode 0600, then changes only paymentFailure to 100%. Restore
posts the exact saved configuration back to flagd-ui. Keep the state file until
the demonstration has been restored successfully.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local exit_code=$?

  trap - EXIT INT TERM
  if [[ -n "${forward_pid}" ]]; then
    kill "${forward_pid}" 2>/dev/null || true
    wait "${forward_pid}" 2>/dev/null || true
  fi
  if [[ -n "${forward_log}" ]]; then
    rm -f -- "${forward_log}"
  fi
  if [[ -n "${transient_file}" ]]; then
    rm -f -- "${transient_file}"
  fi
  exit "${exit_code}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 must be installed."
}

action=""
failure_action=""

while (($# > 0)); do
  case "$1" in
    -e|--environment)
      (($# >= 2)) || die "${1} requires an environment name."
      environment="$2"
      shift 2
      ;;
    -c|--context)
      (($# >= 2)) || die "${1} requires a Kubernetes context."
      kube_context="$2"
      shift 2
      ;;
    -s|--state-file)
      (($# >= 2)) || die "${1} requires a file path."
      state_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    preflight|payment-failure)
      [[ -z "${action}" ]] || die "Only one action may be specified."
      action="$1"
      shift
      ;;
    enable|restore)
      [[ "${action}" == "payment-failure" && -z "${failure_action}" ]] || \
        die "${1} is valid only after payment-failure."
      failure_action="$1"
      shift
      ;;
    --)
      shift
      (($# == 0)) || die "Unexpected positional argument: $1"
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      die "Unknown action or argument: $1"
      ;;
  esac
done

[[ -n "${action}" ]] || {
  usage >&2
  exit 1
}

[[ "${environment}" =~ ^[a-z][a-z0-9-]{0,61}[a-z0-9]$ ]] || die "environment must be a lowercase DNS-style identifier."
readonly workload_namespace="opentelemetry-demo-${environment}"

require_command kubectl
if [[ -n "${kube_context}" ]]; then
  kubectl_cmd+=(--context "${kube_context}")
fi

assert_cluster_access() {
  "${kubectl_cmd[@]}" version --request-timeout=10s >/dev/null 2>&1 || \
    die "Cannot reach the Kubernetes API. Authenticate to GKE or pass --context."
}

preflight() {
  local deployment

  assert_cluster_access
  "${kubectl_cmd[@]}" get namespace "${workload_namespace}" >/dev/null

  printf 'Workload deployment readiness (%s):\n' "${workload_namespace}"
  for deployment in frontend frontend-proxy checkout payment load-generator llm product-reviews; do
    "${kubectl_cmd[@]}" --namespace "${workload_namespace}" get deployment "${deployment}" \
      -o 'custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,AVAILABLE:.status.availableReplicas' \
      --no-headers
  done

  printf '\nShared observability services:\n'
  "${kubectl_cmd[@]}" --namespace "${OBSERVABILITY_NAMESPACE}" get service \
    otel-collector kube-prometheus-stack-prometheus tempo loki-gateway \
    -o 'custom-columns=NAME:.metadata.name,CLUSTER-IP:.spec.clusterIP' --no-headers

  printf '\nGenerated workload Application:\n'
  "${kubectl_cmd[@]}" --namespace argocd get application "opentelemetry-demo-${environment}" \
    -o 'custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' --no-headers

  printf '\nRecent Load Generator logs:\n'
  "${kubectl_cmd[@]}" --namespace "${workload_namespace}" logs deployment/load-generator \
    --tail=20 --prefix
}

service_name() {
  local candidate
  for candidate in frontend-proxy opentelemetry-demo-frontendproxy otel-demo-frontendproxy; do
    if "${kubectl_cmd[@]}" --namespace "${workload_namespace}" get service "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

start_flagd_tunnel() {
  local service
  local attempt

  assert_cluster_access
  service="$(service_name)" || die "No supported frontend-proxy Service exists in ${workload_namespace}."

  if (exec 3<>"/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2>/dev/null; then
    die "localhost port ${LOCAL_PORT} is already in use; set OTEL_DEMO_FLAGD_LOCAL_PORT to an available port."
  fi

  forward_log="$(mktemp -t otel-demo-flagd.XXXXXX.log)"
  "${kubectl_cmd[@]}" --namespace "${workload_namespace}" port-forward --address 127.0.0.1 \
    "service/${service}" "${LOCAL_PORT}:8080" >"${forward_log}" 2>&1 &
  forward_pid=$!

  for ((attempt = 0; attempt < 200; attempt++)); do
    if curl --silent --show-error --fail --connect-timeout 1 --max-time 2 \
      "http://127.0.0.1:${LOCAL_PORT}/feature/api/read" >/dev/null; then
      return 0
    fi
    if ! kill -0 "${forward_pid}" 2>/dev/null; then
      sed 's/^/  /' "${forward_log}" >&2 || true
      die "Could not start the frontend-proxy port-forward."
    fi
    sleep 0.1
  done

  die "Timed out waiting for the flagd-ui API through the frontend proxy."
}

read_flags() {
  curl --silent --show-error --fail --connect-timeout 3 --max-time 10 \
    "http://127.0.0.1:${LOCAL_PORT}/feature/api/read"
}

write_flags() {
  local payload_file="$1"
  curl --silent --show-error --fail --connect-timeout 3 --max-time 10 \
    --header 'Content-Type: application/json' \
    --request POST \
    --data-binary "@${payload_file}" \
    "http://127.0.0.1:${LOCAL_PORT}/feature/api/write" >/dev/null
}

payment_failure_enable() {
  require_command curl
  require_command jq
  [[ -n "${state_file}" ]] || die "payment-failure enable requires --state-file."
  [[ ! -e "${state_file}" ]] || die "state file already exists: ${state_file}"

  start_flagd_tunnel
  umask 077
  read_flags >"${state_file}"
  chmod 600 "${state_file}"

  jq -e '
    .flags.paymentFailure.defaultVariant == "off" and
    .flags.paymentFailure.variants["100%"] == 1
  ' "${state_file}" >/dev/null || die "paymentFailure is not in its expected healthy off state."

  transient_file="$(mktemp -t otel-demo-payment-failure.XXXXXX.json)"
  jq '.flags.paymentFailure.defaultVariant = "100%" | {data: .}' "${state_file}" >"${transient_file}"
  write_flags "${transient_file}"
  rm -f -- "${transient_file}"
  transient_file=""

  [[ "$(read_flags | jq -r '.flags.paymentFailure.defaultVariant')" == "100%" ]] || \
    die "flagd-ui did not confirm the paymentFailure 100% variant."

  printf 'paymentFailure is now 100%%. Restore it with:\n  %q payment-failure restore --state-file %q\n' \
    "$0" "${state_file}"
}

payment_failure_restore() {
  require_command curl
  require_command jq
  [[ -n "${state_file}" ]] || die "payment-failure restore requires --state-file."
  [[ -f "${state_file}" ]] || die "state file was not found: ${state_file}"
  jq -e '.flags.paymentFailure.defaultVariant == "off"' "${state_file}" >/dev/null || \
    die "state file does not contain the original healthy paymentFailure=off configuration."

  start_flagd_tunnel
  transient_file="$(mktemp -t otel-demo-payment-restore.XXXXXX.json)"
  jq '{data: .}' "${state_file}" >"${transient_file}"
  write_flags "${transient_file}"
  rm -f -- "${transient_file}"
  transient_file=""

  [[ "$(read_flags | jq -r '.flags.paymentFailure.defaultVariant')" == "off" ]] || \
    die "flagd-ui did not confirm restoration of paymentFailure=off."

  rm -f -- "${state_file}"
  printf 'Restored the original flagd configuration and removed %s.\n' "${state_file}"
}

case "${action}" in
  preflight)
    [[ -z "${failure_action}" ]] || die "preflight does not accept a failure action."
    preflight
    ;;
  payment-failure)
    [[ -n "${failure_action}" ]] || die "payment-failure requires enable or restore."
    case "${failure_action}" in
      enable)
        payment_failure_enable
        ;;
      restore)
        payment_failure_restore
        ;;
      *)
        die "payment-failure requires enable or restore."
        ;;
    esac
    ;;
  *)
    die "Unknown action: ${action}"
    ;;
esac
