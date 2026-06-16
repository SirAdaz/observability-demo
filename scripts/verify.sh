#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${ROOT_DIR}/.kube/config}"

PASS=0
FAIL=0

ok()   { echo "[OK]   $*"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL + 1)); }
info() { echo "[    ] $*"; }

# ─── helpers ───────────────────────────────────────────────────────────────────

pod_running() {
  local ns="$1" label="$2"
  local count
  count=$(kubectl get pods -n "${ns}" -l "${label}" \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)
  [[ "${count}" -gt 0 ]]
}

prom_query() {
  # Run a PromQL instant query via the Prometheus port-forward (19090).
  # Returns the raw result JSON on stdout.
  curl -sf \
    --max-time 5 \
    "http://localhost:19090/api/v1/query" \
    --data-urlencode "query=$1" 2>/dev/null
}

loki_query() {
  curl -sf \
    --max-time 5 \
    "http://localhost:19090/api/v1/query" \
    --data-urlencode "query=count_over_time({namespace=\"orders\",app=\"orders\"}[5m])" \
    >/dev/null 2>&1
}

# ─── 1. Pods monitoring ────────────────────────────────────────────────────────

info "=== 1. Pods namespace monitoring ==="
kubectl get pods -n monitoring --no-headers 2>/dev/null || true
echo

for deploy in monitoring-grafana monitoring-kube-prometheus-operator \
              monitoring-kube-prometheus-prometheus; do
  if kubectl rollout status -n monitoring "deploy/${deploy}" --timeout=10s \
      >/dev/null 2>&1; then
    ok "deploy/${deploy} Running"
  else
    fail "deploy/${deploy} pas en état Running"
  fi
done

if pod_running monitoring "app=loki"; then
  ok "Loki Running"
else
  fail "Loki pas Running (kubectl get pods -n monitoring -l app=loki)"
fi

if pod_running monitoring "app.kubernetes.io/name=promtail"; then
  ok "Promtail Running"
else
  fail "Promtail pas Running (kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail)"
fi

# ─── 2. Namespace orders ───────────────────────────────────────────────────────

info ""
info "=== 2. Namespace orders ==="

if kubectl rollout status -n orders deploy/orders --timeout=10s >/dev/null 2>&1; then
  ok "deploy/orders Running"
else
  fail "deploy/orders pas Running"
fi

SM_LABEL=$(kubectl get servicemonitor -n orders orders \
  -o jsonpath='{.metadata.labels.release}' 2>/dev/null || echo "")
if [[ "${SM_LABEL}" == "monitoring" ]]; then
  ok "ServiceMonitor orders a le label release=monitoring"
else
  fail "ServiceMonitor orders manque le label release=monitoring (valeur actuelle : '${SM_LABEL}')"
fi

PR_LABEL=$(kubectl get prometheusrule -n orders orders-slo \
  -o jsonpath='{.metadata.labels.release}' 2>/dev/null || echo "")
if [[ "${PR_LABEL}" == "monitoring" ]]; then
  ok "PrometheusRule orders-slo a le label release=monitoring"
else
  fail "PrometheusRule orders-slo manque le label release=monitoring"
fi

# ─── 3. Ressources sample lab06 ───────────────────────────────────────────────

info ""
info "=== 3. Ressources sample lab06 ==="
for res in "deploy/sample" "servicemonitor/sample" "prometheusrule/sample-alerts"; do
  ns="default"
  [[ "${res}" == deploy* ]] && ns="default"
  if kubectl get -n "${ns}" "${res}" >/dev/null 2>&1; then
    ok "${res} présent"
  else
    fail "${res} absent"
  fi
done

# ─── 4. Endpoint /metrics orders ──────────────────────────────────────────────

info ""
info "=== 4. Endpoint /metrics orders ==="

PF_PID=""
cleanup_pf() { [[ -n "${PF_PID}" ]] && kill "${PF_PID}" >/dev/null 2>&1 || true; }
trap cleanup_pf EXIT

# Vérifier si le port-forward est déjà actif
if curl -sf --max-time 2 http://localhost:18080/metrics >/dev/null 2>&1; then
  info "Port 18080 déjà ouvert, pas besoin de port-forward temporaire"
else
  kubectl port-forward -n orders svc/orders 18080:80 \
    >/tmp/orders-verify-pf.log 2>&1 &
  PF_PID=$!
  sleep 3
fi

METRICS_OUT=$(curl -sf --max-time 5 http://localhost:18080/metrics 2>/dev/null || echo "")
for metric in http_requests_total http_request_duration_seconds_bucket \
              orders_total payment_errors_total; do
  if echo "${METRICS_OUT}" | grep -q "${metric}"; then
    ok "métrique ${metric} présente"
  else
    fail "métrique ${metric} absente de /metrics"
  fi
done

if [[ -n "${PF_PID}" ]]; then
  kill "${PF_PID}" >/dev/null 2>&1 || true
  PF_PID=""
fi

# ─── 5. Cible orders UP dans Prometheus ───────────────────────────────────────

info ""
info "=== 5. Cible orders dans Prometheus ==="

if ! curl -sf --max-time 3 http://localhost:19090/-/healthy >/dev/null 2>&1; then
  fail "Prometheus non joignable sur localhost:19090 (lance 'start' ou 'stop && start')"
else
  TARGETS=$(curl -sf --max-time 5 http://localhost:19090/api/v1/targets 2>/dev/null || echo "{}")
  ORDERS_HEALTH=$(echo "${TARGETS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
targets = data.get('data', {}).get('activeTargets', [])
healths = [t['health'] for t in targets if t.get('labels', {}).get('job') == 'orders']
print(','.join(healths) if healths else 'MISSING')
" 2>/dev/null || echo "MISSING")

  if echo "${ORDERS_HEALTH}" | grep -q "up"; then
    ok "Cible orders UP dans Prometheus (health: ${ORDERS_HEALTH})"
  elif [[ "${ORDERS_HEALTH}" == "MISSING" ]]; then
    fail "Cible orders ABSENTE de Prometheus (ServiceMonitor non découvert ?)"
  else
    fail "Cible orders présente mais health=${ORDERS_HEALTH}"
  fi

  SAMPLE_HEALTH=$(echo "${TARGETS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
targets = data.get('data', {}).get('activeTargets', [])
healths = [t['health'] for t in targets if t.get('labels', {}).get('job') == 'sample']
print(','.join(healths) if healths else 'MISSING')
" 2>/dev/null || echo "MISSING")

  if echo "${SAMPLE_HEALTH}" | grep -q "up"; then
    ok "Cible sample UP dans Prometheus"
  else
    fail "Cible sample absente ou down (health: ${SAMPLE_HEALTH})"
  fi
fi

# ─── 6. Données Prometheus pour orders ────────────────────────────────────────

info ""
info "=== 6. Données Prometheus (métriques orders) ==="

if curl -sf --max-time 3 http://localhost:19090/-/healthy >/dev/null 2>&1; then
  REQ_RESULT=$(prom_query 'sum(http_requests_total{job="orders"})' 2>/dev/null || echo "")
  REQ_VALUE=$(echo "${REQ_RESULT}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
res = d.get('data', {}).get('result', [])
print(res[0]['value'][1] if res else '0')
" 2>/dev/null || echo "0")

  if python3 -c "import sys; sys.exit(0 if float('${REQ_VALUE:-0}') > 0 else 1)" 2>/dev/null; then
    ok "http_requests_total{job=orders} = ${REQ_VALUE} (données présentes)"
  else
    info "http_requests_total{job=orders} = 0 (génère du trafic avec : curl http://localhost:18080/orders)"
  fi
fi

# ─── 7. État des alertes ──────────────────────────────────────────────────────

info ""
info "=== 7. Alertes Prometheus ==="

if curl -sf --max-time 3 http://localhost:19090/-/healthy >/dev/null 2>&1; then
  ALERTS=$(curl -sf --max-time 5 \
    "http://localhost:19090/api/v1/rules?type=alert" 2>/dev/null || echo "{}")

  ORDERS_RULES=$(echo "${ALERTS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data.get('data', {}).get('groups', [])
rules = []
for g in groups:
  for r in g.get('rules', []):
    if r.get('type') == 'alerting' and 'orders' in g.get('name', '').lower():
      rules.append(r.get('name','?'))
print(len(rules), ','.join(rules[:5]))
" 2>/dev/null || echo "0 ")

  COUNT=$(echo "${ORDERS_RULES}" | awk '{print $1}')
  NAMES=$(echo "${ORDERS_RULES}" | cut -d' ' -f2-)
  if [[ "${COUNT}" -gt 0 ]]; then
    ok "${COUNT} règles orders chargées dans Prometheus (ex: ${NAMES})"
  else
    fail "Aucune règle PrometheusRule orders trouvée"
  fi

  FIRING=$(echo "${ALERTS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data.get('data', {}).get('groups', [])
firing = []
for g in groups:
  for r in g.get('rules', []):
    if r.get('type') == 'alerting':
      for a in r.get('alerts', []):
        if a.get('state') == 'firing':
          firing.append(r.get('name','?'))
print(','.join(firing) if firing else 'none')
" 2>/dev/null || echo "none")

  if [[ "${FIRING}" == "none" ]]; then
    info "Aucune alerte Firing en ce moment (normal si tu n'as pas déclenché de scénario)"
  else
    ok "Alertes Firing : ${FIRING}"
  fi
fi

# ─── 8. Loki accessible ───────────────────────────────────────────────────────

info ""
info "=== 8. Loki (datasource Grafana) ==="

LOKI_READY=$(kubectl exec -n monitoring statefulset/loki -- \
  wget -qO- 'http://localhost:3100/ready' 2>/dev/null || echo "")
if echo "${LOKI_READY}" | grep -q "ready"; then
  ok "Loki /ready répond"
else
  fail "Loki /ready ne répond pas (kubectl logs -n monitoring statefulset/loki)"
fi

# ─── 9. Génération de trafic ──────────────────────────────────────────────────

info ""
info "=== 9. Génération de trafic (30 requêtes /orders) ==="

if curl -sf --max-time 2 http://localhost:18080/orders >/dev/null 2>&1; then
  for _ in $(seq 1 30); do
    curl -s -o /dev/null "http://localhost:18080/orders" || true
  done
  ok "30 requêtes envoyées vers /orders"
else
  fail "localhost:18080 non joignable — relance './scripts/docker-run.sh start'"
fi

# ─── Résumé ───────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "  Résultat : ${PASS} OK  |  ${FAIL} FAIL"
echo "========================================"

if [[ "${FAIL}" -gt 0 ]]; then
  echo ""
  echo "Des vérifications ont échoué. Relis les [FAIL] ci-dessus."
  exit 1
else
  echo ""
  echo "Tout est bon. Stack prête pour la démo."
fi
