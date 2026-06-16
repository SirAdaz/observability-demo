#!/usr/bin/env bash
set -euo pipefail

PF_CONTAINER="${1:-observability-demo-ui-1}"

wait_for_port() {
  local port="$1"
  local label="$2"

  for _ in $(seq 1 45); do
    if (echo >/dev/tcp/127.0.0.1/"${port}") >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "[start] ERREUR: ${label} inaccessible sur le port ${port}" >&2
  return 1
}

if ! docker ps --format '{{.Names}}' | grep -Fxq "${PF_CONTAINER}"; then
  echo "[start] ERREUR: le conteneur ${PF_CONTAINER} n'est pas en cours d'execution." >&2
  docker logs "${PF_CONTAINER}" 2>&1 || true
  exit 1
fi

wait_for_port 13000 "Grafana"
wait_for_port 19090 "Prometheus"
wait_for_port 19093 "Alertmanager"
wait_for_port 18080 "Orders"
