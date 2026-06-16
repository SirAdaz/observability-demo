# Observability Demo (Kubernetes + Prometheus + Grafana)

Ce projet d�ploie une petite API `orders` instrument�e Prometheus, ainsi qu'une stack d'observabilit� (`kube-prometheus-stack`) dans un cluster Kubernetes local `kind`.

L'objectif est de fournir un lab simple pour :
- exposer des m�triques applicatives ;
- collecter ces m�triques via `ServiceMonitor` ;
- visualiser et alerter avec Grafana/Prometheus/Alertmanager ;
- v�rifier le runtime de bout en bout.

## Pr�requis

Tu as seulement besoin de **Docker** sur la machine h�te.

Le reste des outils (`kubectl`, `helm`, `kind`, `python`) est embarqu� dans le conteneur d'outillage.

## D�marrage rapide (tout en une commande)

```bash
./scripts/docker-run.sh start
```

Cette commande :
1. build l'image d'outillage si n�cessaire ;
2. cr�e ou r�utilise le cluster `kind` ;
3. d�ploie la stack monitoring + l'application `orders` ;
4. lance les port-forwards en arri�re-plan ;
5. affiche les liens `localhost` � ouvrir.

Ensuite, ouvre directement :
- Grafana : http://localhost:13000
- Prometheus : http://localhost:19090
- Alertmanager : http://localhost:19093
- Orders API : http://localhost:18080/orders
- M�triques : http://localhost:18080/metrics

Pour arr�ter les interfaces web :

```bash
./scripts/docker-run.sh stop
```

## Structure rapide

- `app/` : API Python `orders` + m�triques Prometheus.
- `k8s/orders/` : manifests de l'application (deployment, service, servicemonitor, alerts).
- `k8s/monitoring/` : config monitoring (values Helm, dashboard, ressources sample).
- `scripts/run-demo.sh` : d�ploiement complet dans le cluster.
- `scripts/verify.sh` : checks runtime (pods, ressources, m�triques).
- `scripts/docker-run.sh` : point d'entr�e principal (wrapper Docker Compose).
- `scripts/setup-kind.sh` : cr�ation/r�utilisation du cluster `kind`.

## Commandes essentielles

Toutes les commandes ci-dessous sont � lancer depuis la racine du projet.

### Tout lancer d'un coup (recommand�)

```bash
./scripts/docker-run.sh start
```

### Build de l'image d'outillage

```bash
./scripts/docker-run.sh build
```

### Cr�er ou r�utiliser le cluster local

```bash
./scripts/docker-run.sh setup
```

### D�ployer la d�mo compl�te

```bash
./scripts/docker-run.sh demo
```

### V�rifier le runtime

```bash
./scripts/docker-run.sh verify
```

### Ouvrir un shell outill� (debug manuel)

```bash
./scripts/docker-run.sh shell
```

### Supprimer le cluster local

```bash
./scripts/docker-run.sh teardown
```

### Arr�ter les port-forwards

```bash
./scripts/docker-run.sh stop
```

## Workflow recommand�

Pour (re)tester le projet rapidement :

```bash
./scripts/docker-run.sh start
./scripts/docker-run.sh verify
```

En cas de probl�me, relance `start` puis `verify` pour valider l'�tat du cluster.