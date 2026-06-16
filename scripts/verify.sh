#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${ROOT_DIR}/.kube/config}"

echo "[check] Monitoring namespace"
kubectl get pods -n monitoring

echo "[check] Orders deployment"
kubectl get deploy -n orders orders
kubectl get svc -n orders orders
kubectl get servicemonitor -n orders orders -o jsonpath='{.metadata.labels.release}'; echo
kubectl get prometheusrule -n orders orders-slo -o jsonpath='{.metadata.labels.release}'; echo

echo "[check] Sample resources"
kubectl get deploy sample
kubectl get servicemonitor sample
kubectl get prometheusrule sample-alerts

echo "[check] Orders metrics endpoint (port-forward + curl)"
kubectl port-forward -n orders svc/orders 18080:80 >/tmp/orders-pf.log 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" >/dev/null 2>&1 || true' EXIT
sleep 2
curl -fsS "http://localhost:18080/metrics" | rg "http_requests_total|http_request_duration_seconds_bucket" -n

echo "[check] Generate traffic to trigger alert window"
for i in $(seq 1 120); do
  curl -s -o /dev/null "http://localhost:18080/orders" || true
done

echo "[ok] Verification completed"
