#!/usr/bin/env bash
# Read existing dashboard credentials at runtime. This script never writes
# secrets to disk and no credential values are stored in this repository.

set -Eeuo pipefail

readonly DEFAULT_ARGOCD_NAMESPACE="argocd"
readonly DEFAULT_OBSERVABILITY_NAMESPACE="observability"

argocd_namespace="${DEFAULT_ARGOCD_NAMESPACE}"
observability_namespace="${DEFAULT_OBSERVABILITY_NAMESPACE}"
kube_context=""
show_secrets=false

declare -a kubectl_cmd=(kubectl)

usage() {
  cat <<'EOF'
Usage: scripts/get-dashboard-credentials.sh --show-secrets [options]

Print the runtime credentials for the platform dashboards. Values are read
directly from Kubernetes Secrets and are never written to a file.

Options:
  --show-secrets                    Required before password values are printed.
  -c, --context NAME                Use this kubeconfig context.
  --argocd-namespace NAME           Argo CD namespace (default: argocd).
  --observability-namespace NAME    Observability namespace (default: observability).
  -h, --help                        Show this help text.

The script reports Grafana and the Argo CD initial admin secret when present.
Prometheus, Alertmanager, the OpenTelemetry Demo, Loki, and Tempo do not have
platform-managed local usernames or passwords. Loki and Tempo are queried via
Grafana Explore.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --show-secrets)
      show_secrets=true
      shift
      ;;
    -c|--context)
      (($# >= 2)) || die "${1} requires a context name."
      kube_context="$2"
      shift 2
      ;;
    --argocd-namespace)
      (($# >= 2)) || die "${1} requires a namespace."
      argocd_namespace="$2"
      shift 2
      ;;
    --observability-namespace)
      (($# >= 2)) || die "${1} requires a namespace."
      observability_namespace="$2"
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

${show_secrets} || die "Refusing to print credentials without --show-secrets."

command -v kubectl >/dev/null 2>&1 || die "kubectl must be installed and on PATH."
command -v jq >/dev/null 2>&1 || die "jq must be installed and on PATH."

if [[ -n "${kube_context}" ]]; then
  kubectl_cmd+=(--context "${kube_context}")
fi

"${kubectl_cmd[@]}" version --request-timeout=10s >/dev/null 2>&1 || \
  die "Cannot reach the Kubernetes API. Authenticate to GKE or pass --context."

secret_value() {
  local namespace="$1"
  local secret="$2"
  local key="$3"

  "${kubectl_cmd[@]}" --namespace "${namespace}" get secret "${secret}" -o json |
    jq -er --arg key "${key}" '.data[$key] | @base64d'
}

print_missing_secret() {
  local dashboard="$1"
  local namespace="$2"
  local secret="$3"

  printf '%s\n' "${dashboard}: credential secret ${namespace}/${secret} was not found."
}

printf 'Kubernetes context: %s\n\n' \
  "$("${kubectl_cmd[@]}" config current-context 2>/dev/null || printf 'selected context')"

printf '%s\n' 'Grafana'
if "${kubectl_cmd[@]}" --namespace "${observability_namespace}" get secret \
  kube-prometheus-stack-grafana >/dev/null 2>&1; then
  printf '  URL:      http://127.0.0.1:3000\n'
  printf '  Username: %s\n' \
    "$(secret_value "${observability_namespace}" kube-prometheus-stack-grafana admin-user)"
  printf '  Password: %s\n' \
    "$(secret_value "${observability_namespace}" kube-prometheus-stack-grafana admin-password)"
else
  print_missing_secret "Grafana" "${observability_namespace}" kube-prometheus-stack-grafana
fi

printf '\n%s\n' 'Argo CD'
if "${kubectl_cmd[@]}" --namespace "${argocd_namespace}" get secret \
  argocd-initial-admin-secret >/dev/null 2>&1; then
  printf '  URL:      http://127.0.0.1:8080\n'
  printf '  Username: admin\n'
  printf '  Password: %s\n' \
    "$(secret_value "${argocd_namespace}" argocd-initial-admin-secret password)"
  printf '%s\n' '  Note: This is the initial admin password. It may no longer be valid if it was changed.'
else
  print_missing_secret "Argo CD" "${argocd_namespace}" argocd-initial-admin-secret
  printf '%s\n' '  Note: argocd-secret stores only a password hash, not a recoverable password.'
fi

printf '\n%s\n' 'Dashboards without platform-managed local credentials'
printf '%s\n' '  Prometheus: http://127.0.0.1:9090 (no built-in local authentication)'
printf '%s\n' '  Alertmanager: http://127.0.0.1:9093 (no built-in local authentication)'
printf '%s\n' '  OpenTelemetry Demo: http://127.0.0.1:8081 (no built-in local authentication)'
printf '%s\n' '  Loki and Tempo: use Grafana Explore; no separate dashboard credentials.'
