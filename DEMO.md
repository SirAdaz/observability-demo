# Guide de démo — Observability Day

> Marche à suivre complète pour présenter la stack d'observabilité en live.  
> Format attendu : **5–7 min de démo**, puis 2–3 min de questions.  
> **Pas de slides** — pilotez les UIs en direct. Chaque membre du binôme parle de sa moitié.

---

## Pré-requis avant de commencer

- Docker installé sur la machine hôte (c'est tout).
- Être à la racine du repo.

---

## Étape 0 — Démarrer la stack complète

```bash
./scripts/docker-run.sh start
```

Cette commande fait tout d'un coup :
1. Build l'image d'outillage si nécessaire.
2. Crée (ou réutilise) le cluster `kind`.
3. Déploie la stack monitoring + l'application `orders`.
4. Lance les port-forwards en arrière-plan.
5. Affiche les liens `localhost` à ouvrir.

> Lancez cette commande **avant** la démo pour ne pas attendre en live (~3–5 min la première fois).

---

## Étape 1 — Vérifier que tout tourne

```bash
./scripts/docker-run.sh verify
```

Attendez que tous les checks soient verts avant de commencer à présenter.

> Tous les outils (`kubectl`, `helm`, `kind`…) sont embarqués dans le conteneur.  
> Pour lancer des commandes manuelles, ouvrez d'abord un shell outillé :
> ```bash
> ./scripts/docker-run.sh shell
> ```
> Toutes les commandes `kubectl` ci-dessous s'exécutent **dans ce shell**.

```bash
# Nodes du cluster
kubectl get nodes

# Tous les pods (ne doit pas y avoir d'erreurs)
kubectl get pods -A | grep -v Running | grep -v Completed

# Pods de monitoring spécifiquement
kubectl get pods -n monitoring
```

---

## Étape 2 — Ouvrir les UIs (à garder ouvertes pendant la démo)

| Interface | URL |
|-----------|-----|
| Grafana | http://localhost:13000 |
| Prometheus | http://localhost:19090 |
| Alertmanager | http://localhost:19093 |
| Orders API | http://localhost:18080/orders |
| Métriques brutes | http://localhost:18080/metrics |

**Login Grafana :** `admin` / `admin`

---

## Étape 3 — Script de démo (ce que vous montrez, dans l'ordre)

### 3.1 — L'App (responsable App)

1. **Montrer l'endpoint instrumenté**
   - Ouvrir http://localhost:18080/orders → réponse JSON de l'API.
   - Ouvrir http://localhost:18080/metrics → page Prometheus avec les métriques exposées.
   - Pointer les métriques RED : compteur de requêtes, histogram de latence, compteur d'erreurs.

2. **Montrer les logs structurés** (dans `./scripts/docker-run.sh shell`)
   ```bash
   kubectl logs -n orders -l app=orders --tail=20
   ```
   Montrer que chaque ligne est du JSON avec `request_id`, `status_code`, `duration_ms`.

### 3.2 — La Stack (responsable Stack)

3. **Montrer ce qui tourne sur le cluster** (dans `./scripts/docker-run.sh shell`)
   ```bash
   kubectl get pods -n monitoring
   ```
   Citer les composants : Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter.

4. **Montrer que l'app est scrapée**
   - Dans Prometheus → **Status → Targets**.
   - Trouver la cible `orders` → état **UP**.
   - Expliquer le mécanisme : ServiceMonitor + label `release: monitoring` → l'opérateur découvre automatiquement.

5. **PromQL en direct**
   - Dans Prometheus → Graph, taper :
     ```promql
     rate(http_requests_total[1m])
     ```
   - Expliquer le calcul : taux de requêtes par seconde sur 1 min.

### 3.3 — Le dashboard Grafana

6. Ouvrir le dashboard custom dans Grafana.
7. **Dérouler un panel**, expliquer le PromQL derrière (rate, histogram_quantile…).
8. Pointer les trois panneaux RED : **Rate** / **Errors** / **Duration (p99)**.

### 3.4 — Générer du trafic et déclencher une alerte

9. **Générer du trafic normal**
   ```bash
   for i in $(seq 1 20); do curl -s http://localhost:18080/orders > /dev/null; done
   ```

10. **Générer des erreurs** (pour faire passer l'alerte `Pending → Firing`)
    ```bash
    for i in $(seq 1 50); do curl -s http://localhost:18080/orders/invalid > /dev/null; done
    ```

11. **Montrer l'alerte**
    - Dans Prometheus → **Alerts** : trouver la règle sur le taux d'erreurs, état **Pending** puis **Firing**.
    - Ouvrir **Alertmanager** (http://localhost:19093) : l'alerte apparaît dans la liste.
    - Expliquer la règle : seuil, durée de déclenchement (`for:`), labels.

### 3.5 — La passation (les deux ensemble)

12. Expliquer **comment La Stack découvre L'App** :
    - L'App dépose un `ServiceMonitor` avec le label `release: monitoring`.
    - L'opérateur Prometheus surveille tous les `ServiceMonitor` portant ce label.
    - Il ajoute automatiquement la cible → scraping toutes les 15 s.

    > C'est le piège n°1 : un ServiceMonitor **sans** ce label est ignoré silencieusement.

---

## Étape 4 — (Optionnel) 3ᵉ pilier : Logs ou Traces

### Track Logs (Loki)
- Ouvrir Grafana → **Explore** → source **Loki**.
- Requête LogQL sur les logs de l'app :
  ```logql
  {app="orders"} | json | status_code >= 500
  ```
- Montrer comment sauter d'un pic de métrique → lignes de log correspondantes.

### Track Traces (Tempo)
- Ouvrir Grafana → **Explore** → source **Tempo**.
- Lancer une requête TraceQL ou cliquer un exemplar depuis un panel de métriques.
- Montrer l'arbre de trace distribuée.

---

## Étape 5 — Ce qui a cassé (obligatoire en démo !)

> Les 60 secondes les plus utiles de la démo.

Préparez une anecdote honnête sur ce qui a foiré pendant l'intégration et comment vous l'avez réparé. Exemples courants :
- ServiceMonitor déployé sans le label `release: monitoring` → cible jamais visible dans Prometheus.
- Image Docker non chargée dans kind avec `kind load docker-image` → `ImagePullBackOff`.
- Port-forward qui tombe → relancer `./scripts/docker-run.sh start`.

---

## Grille d'évaluation (rappel)

| Critère | Ce que « bien » veut dire |
|---------|---------------------------|
| **Ça marche** | App qui tourne, scrapée par La Stack, UIs accessibles |
| **La passation** | Vous expliquez le ServiceMonitor + le label |
| **Compréhension** | Chaque responsable explique le *pourquoi* (que calcule ce PromQL ?) |
| **Alerting** | Alerte qui se déclenche sur L'App, seuil sensé, visible dans Alertmanager |
| **3ᵉ pilier** | Logs ou traces fonctionnels sur votre app (si fait) |
| **Travail d'équipe** | Les deux parlent, chacun possède sa moitié |
| **Communication** | Clair, honnête sur ce qui a cassé, dans les 7 min |

---

## Aide-mémoire rapide

```bash
# Tout démarrer
./scripts/docker-run.sh start

# Vérifier l'état
./scripts/docker-run.sh verify

# Shell de debug (kubectl, helm, etc.)
./scripts/docker-run.sh shell

# Arrêter les port-forwards
./scripts/docker-run.sh stop

# Détruire le cluster
./scripts/docker-run.sh teardown
```

> Les commandes `kubectl` / `helm` n'existent pas en local — elles tournent dans le conteneur.  
> Ouvrez un shell outillé avec `./scripts/docker-run.sh shell`, puis lancez-les dedans.
