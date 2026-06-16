#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
CMD="${1:-help}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required on the host to run this project without local tooling." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not running." >&2
  exit 1
fi

case "${CMD}" in
  build)
    docker compose -f "${COMPOSE_FILE}" build tooling
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
