#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-observability-demo}"
export KUBECONFIG="${KUBECONFIG:-${ROOT_DIR}/.kube/config}"

echo "[1/7] Helm repo setup"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "[2/7] Install/upgrade kube-prometheus-stack"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 65.8.1 \
  -f "${ROOT_DIR}/k8s/monitoring/kube-prometheus-values.yaml"

echo "[3/7] Wait monitoring pods"
kubectl rollout status -n monitoring deploy/monitoring-grafana --timeout=240s

echo "[4/7] Build and load orders image"
docker build -t orders:lab03 "${ROOT_DIR}/app"
kind load docker-image orders:lab03 --name "${KIND_CLUSTER_NAME}"

echo "[5/7] Deploy orders namespace and workload"
kubectl create namespace orders --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n orders -f "${ROOT_DIR}/k8s/orders/deployment.yaml"
kubectl apply -n orders -f "${ROOT_DIR}/k8s/orders/service.yaml"
kubectl apply -n orders -f "${ROOT_DIR}/k8s/orders/servicemonitor.yaml"
kubectl apply -n orders -f "${ROOT_DIR}/k8s/orders/alerts.yaml"
kubectl rollout status -n orders deploy/orders --timeout=120s

echo "[6/7] Deploy sample lab06 resources"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/01-sample-app.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/02-sample-servicemonitor.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/03-sample-alert-rule.yaml"

echo "[7/7] Apply Grafana dashboard"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/orders-dashboard-configmap.yaml"

echo
echo "Done. Open UIs with:"
echo "  kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
echo "  kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090"
echo "  kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093"
