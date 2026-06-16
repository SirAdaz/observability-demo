#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${ROOT_DIR}/.kube/config}"
export KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-observability-demo}"

usage() {
  cat <<'EOF'
Usage: ./scripts/docker-run.sh <command>

Commands:
  build       Build the tooling image
  setup       Create or reuse the local kind cluster
  demo        Deploy monitoring stack and demo workloads
  deploy      Alias of demo (used by start)
  verify      Run runtime verification checks
  ui          Keep port-forwards running for local UIs
  shell       Open an interactive shell with all tools available
  teardown    Delete the kind cluster

Only Docker is required on the host.
EOF
}

run_cmd() {
  case "${1:-shell}" in
    build)
      docker compose -f "${ROOT_DIR}/docker-compose.yml" build tooling
      ;;
    setup)
      "${ROOT_DIR}/scripts/setup-kind.sh"
      ;;
    demo|deploy)
      "${ROOT_DIR}/scripts/setup-kind.sh"
      "${ROOT_DIR}/scripts/run-demo.sh"
      ;;
    ui)
      exec "${ROOT_DIR}/scripts/port-forward-ui.sh"
      ;;
    verify)
      "${ROOT_DIR}/scripts/setup-kind.sh"
      "${ROOT_DIR}/scripts/verify.sh"
      ;;
    shell)
      exec bash
      ;;
    teardown)
      kind delete cluster --name "${KIND_CLUSTER_NAME}" || true
      rm -f "${KUBECONFIG}"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "Unknown command: ${1}" >&2
      usage >&2
      exit 1
      ;;
  esac
}

if [[ -f /.dockerenv ]]; then
  run_cmd "${@:-shell}"
else
  echo "This entrypoint is meant to run inside the tooling container." >&2
  exit 1
fi
