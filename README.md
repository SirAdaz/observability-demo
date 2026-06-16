# Observability Demo — Kubernetes + Prometheus + Grafana + Loki

Lab complet de la journée challenge observabilité. Une API `orders` instrumentée tourne sur un
cluster `kind` local et est entièrement surveillée : métriques RED, alertes, logs centralisés.

---

## Prérequis

Un seul outil à installer : **Docker**.

`kubectl`, `helm`, `kind` et Python sont embarqués dans le conteneur d'outillage.

---

## Démarrage rapide

```bash
./scripts/docker-run.sh start
```

Ça fait tout : cluster kind, stack monitoring, app orders, Loki, Promtail, port-forwards.

### Liens à ouvrir (WSL → navigateur Windows)

> `localhost` ne fonctionne pas depuis le navigateur Windows sous WSL.
> Utilise l'**IP WSL** affichée à la fin de `start` (ex. `172.27.x.x`).

| UI | URL WSL | URL locale (terminal) |
|----|---------|----------------------|
| Console démo | `http://<IP-WSL>:18080/` | `http://localhost:18080/` |
| Grafana | `http://<IP-WSL>:13000` | `http://localhost:13000` |
| Prometheus | `http://<IP-WSL>:19090` | `http://localhost:19090` |
| Alertmanager | `http://<IP-WSL>:19093` | `http://localhost:19093` |
| `/metrics` brut | `http://<IP-WSL>:18080/metrics` | — |

Login Grafana : `admin` / `admin`

---

## Architecture

```
kind (cluster local)
├── namespace: monitoring
│   ├── kube-prometheus-stack  (Prometheus + Grafana + Alertmanager)
│   ├── loki                   (centralisation des logs)
│   └── promtail               (collecte des logs pods → Loki)
└── namespace: orders
    ├── deployment/orders      (API Flask instrumentée)
    ├── servicemonitor/orders  (label release: monitoring → découverte auto)
    └── prometheusrule/orders-slo  (13 règles d'alerte)
```

---

## Checkpoints challenge

### Checkpoint 1 — « Stack debout, App buildée »

- [ ] `kubectl get pods -n monitoring` → tous Running
- [ ] Prometheus → Status → Targets → cible `sample` **UP**
- [ ] Dashboard **orders RED** visible dans Grafana
- [ ] Image `orders:lab03` buildée et chargée dans kind

```bash
./scripts/docker-run.sh verify
```

### Checkpoint 2 — « L'App est observée »

- [ ] Targets Prometheus → cible `orders` **UP** (job="orders")
- [ ] Dashboard **orders RED** : panels R/E/D avec données
- [ ] Alerte `OrdersHighErrorRate` → **Firing** dans Alertmanager

**Comment déclencher l'alerte :**

1. Ouvre `http://<IP-WSL>:18080/`
2. Clique **Taux d'erreur 5xx** (bouton Déclencher)
3. Attends ~1 min → Prometheus → Alerts → `OrdersHighErrorRate` passe Pending puis Firing
4. Alertmanager → `http://<IP-WSL>:19093` → alerte visible

### Checkpoint 3 — « 3e pilier : Logs »

- [ ] Loki Running : `kubectl get pods -n monitoring -l app=loki`
- [ ] Dashboard **orders Logs (Loki)** dans Grafana → requête LogQL retourne des données
- [ ] Après clic sur « Déclencher » : log `event="alert_scenario_triggered"` visible

**Requêtes LogQL utiles :**

```logql
# Toutes les requêtes HTTP
{namespace="orders", app="orders"} | json | event="request_completed"

# Erreurs uniquement
{namespace="orders", app="orders"} | json | status=~"5.."

# Logs de scénario déclenchés
{namespace="orders", app="orders"} | json | event="alert_scenario_triggered"
```

---

## Script de démo (5–7 min)

### 1 · L'App instrumentée (personne App)

```bash
# Montrer l'endpoint /metrics brut
curl http://localhost:18080/metrics | grep -E "http_requests_total|orders_total"

# Montrer les logs structurés JSON
kubectl logs -n orders deploy/orders --tail=5
```

Ouvrir `http://<IP-WSL>:18080/` → montrer le catalogue d'alertes + terminal logs.

### 2 · La stack qui tourne (personne Stack)

```bash
kubectl get pods -n monitoring
kubectl get pods -n orders
```

Prometheus → Status → Targets → montrer `orders` **UP** avec le label `job="orders"`.
Expliquer le `ServiceMonitor` + le label `release: monitoring` (piège n°1).

### 3 · Dashboard + PromQL

Grafana → **orders RED** → panel « E - Error ratio by route » → expliquer :

```promql
sum by (route) (
  rate(http_requests_total{job="orders", status=~"5.."}[5m])
)
/
sum by (route) (
  rate(http_requests_total{job="orders"}[5m])
)
```

### 4 · Alerte qui se déclenche

Console → cliquer **Taux d'erreur 5xx** → revenir dans :

- Prometheus → Alerts → `OrdersHighErrorRate` → Pending (attendre `for: 1m`)
- Alertmanager → alerte Firing

### 5 · 3e pilier — Logs (Loki)

Grafana → **orders Logs (Loki)** → montrer les panels.

Ouvrir Explore → datasource **Loki** → requête :

```logql
{namespace="orders", app="orders"} | json | event="alert_scenario_triggered"
```

### 6 · Ce qui a cassé (obligatoire)

Choses réelles qui ont cassé pendant le montage :

- **ServiceMonitor sans `release: monitoring`** → cible jamais découverte, silencieusement ignorée
- **Dashboards « No data »** → requêtes filtraient sur `app="orders"` mais Prometheus expose `job="orders"`
- **Loki CrashLoop** → `/var/loki` en read-only filesystem → corrigé avec `emptyDir`
- **WSL `localhost` refusé** → les port-forwards bindent `0.0.0.0` mais le navigateur Windows ne touche pas localhost WSL → utiliser l'IP WSL

---

## Commandes essentielles

```bash
# Tout lancer (recommandé)
./scripts/docker-run.sh start

# Vérifier le runtime complet
./scripts/docker-run.sh verify

# Reconstruire et redéployer l'app orders seulement
./scripts/docker-run.sh redeploy

# Shell outillé (kubectl, helm, etc.)
./scripts/docker-run.sh shell

# Arrêter les port-forwards
./scripts/docker-run.sh stop

# Détruire le cluster
./scripts/docker-run.sh teardown
```

### Debug manuel (dans le shell outillé)

```bash
# Pods en erreur ?
kubectl get pods -A | grep -Ev "Running|Completed"

# Logs orders
kubectl logs -n orders deploy/orders -f

# Métriques orders (depuis le cluster)
kubectl exec -n orders deploy/orders -- wget -qO- localhost:80/metrics | head -20

# Prometheus scrape orders ?
curl -s http://localhost:19090/api/v1/targets | python3 -m json.tool | grep -A5 '"job":"orders"'

# LogQL depuis le cluster
kubectl exec -n monitoring statefulset/loki -- wget -qO- \
  'http://localhost:3100/loki/api/v1/query?query=\{namespace="orders"\}&limit=3'
```

---

## Structure du projet

```
app/                    API Flask orders
  app.py                métriques Prometheus (Counter, Histogram, Gauge)
  alerts.py             catalogue de scénarios + simulation soutenue
  log_buffer.py         logs JSON structurés + SSE pour la console
  templates/index.html  console web de démo
k8s/
  orders/
    deployment.yaml     pod orders
    service.yaml        service + port "metrics"
    servicemonitor.yaml découverte Prometheus (label release: monitoring)
    alerts.yaml         13 règles PrometheusRule
  monitoring/
    kube-prometheus-values.yaml   config Helm + datasource Loki
    loki-values.yaml              Loki (mode single binary)
    promtail-values.yaml          collecte logs pods
    orders-dashboard-configmap.yaml     dashboard "orders RED"
    orders-logs-dashboard-configmap.yaml dashboard "orders Logs (Loki)"
    01-sample-app.yaml            app d'exemple lab06
    02-sample-servicemonitor.yaml ServiceMonitor exemple
    03-sample-alert-rule.yaml     PrometheusRule exemple
scripts/
  docker-run.sh         point d'entrée principal
  run-demo.sh           déploiement complet dans kind
  verify.sh             checks runtime
  setup-kind.sh         création/réutilisation cluster kind
  port-forward-ui.sh    port-forwards vers 0.0.0.0
  print-success.sh      affiche les liens à la fin de start
```

---

## Métriques exposées par l'app

| Métrique | Type | Description |
|----------|------|-------------|
| `http_requests_total` | Counter | Requêtes par méthode, route, status |
| `http_request_duration_seconds` | Histogram | Latence (buckets 5ms → 10s) |
| `orders_total` | Counter | Ordres créés/échoués |
| `orders_in_flight` | Gauge | Ordres en cours |
| `orders_queue_depth` | Gauge | Profondeur de queue simulée |
| `payment_errors_total` | Counter | Erreurs paiement par raison |
| `db_errors_total` | Counter | Erreurs DB par opération |
| `cache_hits_total` | Counter | Cache hits |
| `cache_misses_total` | Counter | Cache misses |
| `orders_app_info` | Info | Version, env, région |

---

## Piège n°1 de l'intégration

Un `ServiceMonitor` **sans** le label `release: monitoring` est ignoré **silencieusement**
par l'opérateur Prometheus. La cible de l'app n'apparaît jamais dans Targets.

Vérifier :

```bash
kubectl get servicemonitor -n orders orders -o jsonpath='{.metadata.labels.release}'
# doit afficher : monitoring
```
