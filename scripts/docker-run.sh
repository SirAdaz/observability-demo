#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
PF_CONTAINER="observability-demo-ui-1"
CMD="${1:-help}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required on the host to run this project without local tooling." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not running." >&2
  exit 1
fi

ensure_image() {
  if ! docker image inspect observability-demo-tooling:latest >/dev/null 2>&1; then
    echo "[start] Image d'outillage absente, build en cours..."
    docker compose -f "${COMPOSE_FILE}" build tooling
  fi
}

start_demo() {
  ensure_image
  echo "[start] Deploiement du cluster et des workloads..."
  docker compose -f "${COMPOSE_FILE}" run --rm tooling deploy

  docker compose -f "${COMPOSE_FILE}" rm -sf ui >/dev/null 2>&1 || true
  echo "[start] Lancement des interfaces web sur localhost..."
  docker compose -f "${COMPOSE_FILE}" up -d ui >/dev/null

  "${ROOT_DIR}/scripts/wait-for-ui.sh" "${PF_CONTAINER}"
  "${ROOT_DIR}/scripts/print-success.sh"
}

stop_demo() {
  if docker compose -f "${COMPOSE_FILE}" rm -sf ui >/dev/null 2>&1; then
    echo "Interfaces web arretees."
  else
    echo "Aucun port-forward actif (service ui introuvable)."
  fi
}

case "${CMD}" in
  build)
    docker compose -f "${COMPOSE_FILE}" build tooling
    ;;
  start)
    start_demo
    ;;
  redeploy)
    echo "[redeploy] Rebuild image orders + restart pods + port-forwards..."
    docker compose -f "${COMPOSE_FILE}" run --rm --entrypoint /bin/bash tooling -c \
      'docker build -t orders:lab03 /workspace/app && kind load docker-image orders:lab03 --name observability-demo && kubectl rollout restart -n orders deploy/orders && kubectl rollout status -n orders deploy/orders --timeout=120s'
    docker compose -f "${COMPOSE_FILE}" rm -sf ui >/dev/null 2>&1 || true
    docker compose -f "${COMPOSE_FILE}" up -d ui >/dev/null
    "${ROOT_DIR}/scripts/wait-for-ui.sh"
    "${ROOT_DIR}/scripts/print-success.sh"
    ;;
  stop)
    stop_demo
    ;;
  setup|demo|verify|shell|teardown|help|-h|--help)
    docker compose -f "${COMPOSE_FILE}" run --rm tooling "${CMD}"
    ;;
  *)
    echo "Unknown command: ${CMD}" >&2
    docker compose -f "${COMPOSE_FILE}" run --rm tooling help
    exit 1
    ;;
esac
