#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${KIND_CLUSTER_NAME:-observability-demo}"
KUBECONFIG_PATH="${KUBECONFIG:-${ROOT_DIR}/.kube/config}"
KIND_CONFIG="${ROOT_DIR}/docker/kind-config.yaml"

mkdir -p "$(dirname "${KUBECONFIG_PATH}")"

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not reachable. Mount /var/run/docker.sock or start Docker." >&2
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -Fxq "${CLUSTER_NAME}"; then
  echo "[setup] Creating kind cluster '${CLUSTER_NAME}'"
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --kubeconfig "${KUBECONFIG_PATH}" \
    --config "${KIND_CONFIG}"
else
  echo "[setup] Reusing existing kind cluster '${CLUSTER_NAME}'"
  kind export kubeconfig \
    --name "${CLUSTER_NAME}" \
    --kubeconfig "${KUBECONFIG_PATH}"
fi

export KUBECONFIG="${KUBECONFIG_PATH}"

for _ in $(seq 1 30); do
  if kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
kubectl get nodes
echo "[setup] Cluster ready (kubeconfig: ${KUBECONFIG_PATH})"
