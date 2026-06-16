#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
PF_CONTAINER="observability-demo-pf"
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

  docker rm -f "${PF_CONTAINER}" >/dev/null 2>&1 || true
  echo "[start] Lancement des interfaces web sur localhost..."
  docker compose -f "${COMPOSE_FILE}" run -d --name "${PF_CONTAINER}" tooling ui >/dev/null

  "${ROOT_DIR}/scripts/print-success.sh"
}

stop_demo() {
  if docker rm -f "${PF_CONTAINER}" >/dev/null 2>&1; then
    echo "Interfaces web arretees."
  else
    echo "Aucun port-forward actif (${PF_CONTAINER} introuvable)."
  fi
}

case "${CMD}" in
  build)
    docker compose -f "${COMPOSE_FILE}" build tooling
    ;;
  start)
    start_demo
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
