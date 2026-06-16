#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${ROOT_DIR}/.kube/config}"

PIDS=()

cleanup() {
  for pid in "${PIDS[@]}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
}

trap cleanup EXIT INT TERM

start_forward() {
  local namespace="$1"
  local service="$2"
  local local_port="$3"
  local remote_port="$4"

  kubectl port-forward \
    --address 127.0.0.1,0.0.0.0 \
    -n "${namespace}" \
    "svc/${service}" \
    "${local_port}:${remote_port}" &
  PIDS+=("$!")
}

echo "[ui] Demarrage des port-forwards..."

start_forward monitoring monitoring-grafana 3000 80
start_forward monitoring monitoring-kube-prometheus-prometheus 9090 9090
start_forward monitoring monitoring-kube-prometheus-alertmanager 9093 9093
start_forward orders orders 18080 80

sleep 2
echo "[ui] Port-forwards actifs. Appuyez sur Ctrl+C pour arreter."

wait
