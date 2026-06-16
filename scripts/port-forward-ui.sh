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

wait_for_port() {
  local port="$1"
  local label="$2"

  for _ in $(seq 1 45); do
    if (echo >/dev/tcp/127.0.0.1/"${port}") >/dev/null 2>&1; then
      echo "[ui] ${label} disponible sur le port ${port}"
      return 0
    fi
    sleep 1
  done

  echo "[ui] ERREUR: ${label} indisponible sur le port ${port}" >&2
  return 1
}

start_forward() {
  local namespace="$1"
  local service="$2"
  local local_port="$3"
  local remote_port="$4"

  echo "[ui] port-forward ${service} -> 0.0.0.0:${local_port}"
  kubectl port-forward \
    --address 0.0.0.0 \
    -n "${namespace}" \
    "svc/${service}" \
    "${local_port}:${remote_port}" &
  PIDS+=("$!")
}

echo "[ui] Demarrage des port-forwards..."

start_forward monitoring monitoring-grafana 13000 80
start_forward monitoring monitoring-kube-prometheus-prometheus 19090 9090
start_forward monitoring monitoring-kube-prometheus-alertmanager 19093 9093
start_forward orders orders 18080 80

sleep 2

wait_for_port 13000 "Grafana"
wait_for_port 19090 "Prometheus"
wait_for_port 19093 "Alertmanager"
wait_for_port 18080 "Orders"

echo "[ui] Tous les port-forwards sont actifs."

wait
