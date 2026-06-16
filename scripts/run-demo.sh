#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-observability-demo}"
export KUBECONFIG="${KUBECONFIG:-${ROOT_DIR}/.kube/config}"

echo "[1/10] Helm repo setup"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "[2/10] Install/upgrade kube-prometheus-stack"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 65.8.1 \
  -f "${ROOT_DIR}/k8s/monitoring/kube-prometheus-values.yaml"

echo "[3/10] Install/upgrade Loki"
helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --version 6.24.0 \
  -f "${ROOT_DIR}/k8s/monitoring/loki-values.yaml"

echo "[4/10] Install/upgrade Promtail"
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  --version 6.16.6 \
  -f "${ROOT_DIR}/k8s/monitoring/promtail-values.yaml"

echo "[5/10] Wait monitoring pods"
kubectl rollout status -n monitoring deploy/monitoring-grafana --timeout=240s
kubectl rollout status -n monitoring statefulset/loki --timeout=240s || \
  kubectl rollout status -n monitoring deploy/loki --timeout=240s || true
kubectl rollout status -n monitoring daemonset/promtail --timeout=240s

echo "[6/10] Build and load orders image"
docker build -t orders:lab03 "${ROOT_DIR}/app"
kind load docker-image orders:lab03 --name "${KIND_CLUSTER_NAME}"

echo "[7/10] Deploy orders namespace and workload"
kubectl create namespace orders --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n orders -f "${ROOT_DIR}/k8s/orders/deployment.yaml"
kubectl apply -n orders -f "${ROOT_DIR}/k8s/orders/service.yaml"
kubectl apply -n orders -f "${ROOT_DIR}/k8s/orders/servicemonitor.yaml"
kubectl apply -n orders -f "${ROOT_DIR}/k8s/orders/alerts.yaml"
kubectl rollout status -n orders deploy/orders --timeout=120s

echo "[8/10] Deploy sample lab06 resources"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/01-sample-app.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/02-sample-servicemonitor.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/03-sample-alert-rule.yaml"

echo "[9/10] Apply Grafana dashboards"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/orders-dashboard-configmap.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/monitoring/orders-logs-dashboard-configmap.yaml"

echo "[10/10] Generate sample traffic for logs"
kubectl run logs-traffic-once \
  --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 \
  -n orders \
  --command -- sh -c 'for i in $(seq 1 30); do curl -s -o /dev/null http://orders.orders.svc/orders; done' \
  >/dev/null 2>&1 || true

echo
echo "Done. Open UIs with:"
echo "  Grafana (metrics + logs): port-forward 13000"
echo "  Prometheus: port-forward 19090"
echo "  Alertmanager: port-forward 19093"
echo "  Orders console: port-forward 18080"
echo
echo "Grafana dashboards:"
echo "  - orders RED (metriques)"
echo "  - orders Logs (Loki) - LogQL + correlation metrique/logs"
