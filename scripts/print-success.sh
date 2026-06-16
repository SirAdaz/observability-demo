#!/usr/bin/env bash

cat <<'EOF'

========================================
  Tout est bon, la demo est prete !
========================================

  Grafana       http://localhost:3000
  Prometheus    http://localhost:9090
  Alertmanager  http://localhost:9093
  Orders API    http://localhost:18080/orders
  Metriques     http://localhost:18080/metrics

Pour arreter les interfaces web :
  ./scripts/docker-run.sh stop

EOF
