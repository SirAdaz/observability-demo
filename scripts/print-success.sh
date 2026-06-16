#!/usr/bin/env bash

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -z "${HOST_IP}" ]]; then
  HOST_IP="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
fi

cat <<EOF

========================================
  Tout est bon, la demo est prete !
========================================

EOF

if [[ -n "${HOST_IP}" ]]; then
  cat <<EOF
Liens a ouvrir (WSL / navigateur Windows) :
  Grafana       http://${HOST_IP}:13000
  Prometheus    http://${HOST_IP}:19090
  Alertmanager  http://${HOST_IP}:19093
  Orders API    http://${HOST_IP}:18080/orders
  Metriques     http://${HOST_IP}:18080/metrics

EOF
fi

cat <<'EOF'
Liens locaux (depuis le terminal WSL uniquement) :
  Grafana       http://127.0.0.1:13000
  Prometheus    http://127.0.0.1:19090
  Alertmanager  http://127.0.0.1:19093
  Orders API    http://127.0.0.1:18080/orders
  Metriques     http://127.0.0.1:18080/metrics

Note WSL : si localhost refuse la connexion dans le navigateur,
utilise les liens avec l'IP WSL ci-dessus.

Pour arreter les interfaces web :
  ./scripts/docker-run.sh stop

EOF
