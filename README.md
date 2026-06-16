# Observability Demo (Kubernetes + Prometheus + Grafana)

Ce projet déploie une petite API `orders` instrumentée Prometheus, ainsi qu'une stack d'observabilité (`kube-prometheus-stack`) dans un cluster Kubernetes local `kind`.

L'objectif est de fournir un lab simple pour :
- exposer des métriques applicatives ;
- collecter ces métriques via `ServiceMonitor` ;
- visualiser et alerter avec Grafana/Prometheus/Alertmanager ;
- vérifier le runtime de bout en bout.

## Prérequis

Tu as seulement besoin de **Docker** sur la machine hôte.

Le reste des outils (`kubectl`, `helm`, `kind`, `python`) est embarqué dans le conteneur d'outillage.

## Démarrage rapide (tout en une commande)

```bash
./scripts/docker-run.sh start
```

Cette commande :
1. build l'image d'outillage si nécessaire ;
2. crée ou réutilise le cluster `kind` ;
3. déploie la stack monitoring + l'application `orders` ;
4. lance les port-forwards en arrière-plan ;
5. affiche les liens `localhost` à ouvrir.

Ensuite, ouvre directement :
- Grafana : http://localhost:13000
- Prometheus : http://localhost:19090
- Alertmanager : http://localhost:19093
- Orders API : http://localhost:18080/orders
- Métriques : http://localhost:18080/metrics

Pour arrêter les interfaces web :

```bash
./scripts/docker-run.sh stop
```

## Structure rapide

- `app/` : API Python `orders` + métriques Prometheus.
- `k8s/orders/` : manifests de l'application (deployment, service, servicemonitor, alerts).
- `k8s/monitoring/` : config monitoring (values Helm, dashboard, ressources sample).
- `scripts/run-demo.sh` : déploiement complet dans le cluster.
- `scripts/verify.sh` : checks runtime (pods, ressources, métriques).
- `scripts/docker-run.sh` : point d'entrée principal (wrapper Docker Compose).
- `scripts/setup-kind.sh` : création/réutilisation du cluster `kind`.

## Commandes essentielles

Toutes les commandes ci-dessous sont à lancer depuis la racine du projet.

### Tout lancer d'un coup (recommandé)

```bash
./scripts/docker-run.sh start
```

### Build de l'image d'outillage

```bash
./scripts/docker-run.sh build
```

### Créer ou réutiliser le cluster local

```bash
./scripts/docker-run.sh setup
```

### Déployer la démo complète

```bash
./scripts/docker-run.sh demo
```

### Vérifier le runtime

```bash
./scripts/docker-run.sh verify
```

### Ouvrir un shell outillé (debug manuel)

```bash
./scripts/docker-run.sh shell
```

### Supprimer le cluster local

```bash
./scripts/docker-run.sh teardown
```

### Arrêter les port-forwards

```bash
./scripts/docker-run.sh stop
```

## Workflow recommandé

Pour (re)tester le projet rapidement :

```bash
./scripts/docker-run.sh start
./scripts/docker-run.sh verify
```

En cas de problème, relance `start` puis `verify` pour valider l'état du cluster.

## Commandes Git utiles (pour push sans bug)

### Voir l'état de la branche

```bash
git status
git log --oneline --decorate -n 5
```

### Push standard

```bash
git push origin main
```

### Si la branche locale et distante divergent

```bash
git push --force-with-lease origin main
```

`--force-with-lease` est préférable à `--force` car il évite d'écraser des changements distants inattendus.
