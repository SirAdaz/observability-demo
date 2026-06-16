from __future__ import annotations

import logging
import random
import time
import uuid
from dataclasses import asdict, dataclass

log = logging.getLogger("orders")


@dataclass(frozen=True)
class AlertScenario:
    id: str
    name: str
    severity: str
    group: str
    description: str
    prometheus_alert: str
    trigger_hint: str


ALERT_SCENARIOS: list[AlertScenario] = [
    AlertScenario(
        id="errors",
        name="Taux d'erreur 5xx",
        severity="critical",
        group="orders.errors",
        description="Simule une vague d'erreurs HTTP 500 sur GET /orders.",
        prometheus_alert="OrdersHighErrorRate",
        trigger_hint="Envoie ~40 requetes internes en erreur.",
    ),
    AlertScenario(
        id="payment",
        name="Erreurs de paiement",
        severity="critical",
        group="orders.errors",
        description="Incremente payment_errors_total (declined + timeout).",
        prometheus_alert="OrdersPaymentErrors",
        trigger_hint="Declenche des echecs de paiement repetes.",
    ),
    AlertScenario(
        id="database",
        name="Erreurs base de donnees",
        severity="warning",
        group="orders.errors",
        description="Incremente db_errors_total sur select/delete.",
        prometheus_alert="OrdersDatabaseErrors",
        trigger_hint="Simule des erreurs DB consecutives.",
    ),
    AlertScenario(
        id="404",
        name="Pic de 404",
        severity="warning",
        group="orders.errors",
        description="Genere beaucoup de GET /orders/<id> en 404.",
        prometheus_alert="Orders404SpikeRoute",
        trigger_hint="Envoie des requetes vers des IDs inconnus.",
    ),
    AlertScenario(
        id="latency",
        name="Latence P99 elevee",
        severity="warning",
        group="orders.latency",
        description="Produit des requetes GET /orders tres lentes (> 500ms).",
        prometheus_alert="OrdersHighLatencyP99",
        trigger_hint="Lance des lectures lentes sur la base.",
    ),
    AlertScenario(
        id="slow-post",
        name="Latence POST elevee",
        severity="warning",
        group="orders.latency",
        description="Ralentit les creations d'ordre (POST /orders).",
        prometheus_alert="OrdersHighLatencyP50",
        trigger_hint="Cree des ordres avec delai artificiel.",
    ),
    AlertScenario(
        id="queue",
        name="File d'attente saturee",
        severity="warning",
        group="orders.queue",
        description="Pousse orders_queue_depth au-dessus du seuil.",
        prometheus_alert="OrdersQueueDepthHigh",
        trigger_hint="Augmente la profondeur de queue simulee.",
    ),
    AlertScenario(
        id="in-flight",
        name="Ordres en cours",
        severity="info",
        group="orders.queue",
        description="Maintient orders_in_flight eleve pendant quelques secondes.",
        prometheus_alert="OrdersManyInFlight",
        trigger_hint="Lance des POST lents en parallele.",
    ),
    AlertScenario(
        id="cache",
        name="Cache inefficace",
        severity="info",
        group="orders.slo",
        description="Genere surtout des cache_misses_total.",
        prometheus_alert="OrdersCacheHitRateLow",
        trigger_hint="Force des misses cache sur les lectures.",
    ),
    AlertScenario(
        id="traffic",
        name="Pic de trafic",
        severity="info",
        group="orders.traffic",
        description="Augmente le debit sur POST /orders.",
        prometheus_alert="OrdersHighThroughput",
        trigger_hint="Rafale de creations d'ordre.",
    ),
    AlertScenario(
        id="slo-burn",
        name="Burn rate SLO",
        severity="critical",
        group="orders.slo",
        description="Combine erreurs 5xx + latence pour stresser le SLO.",
        prometheus_alert="OrdersSLOBurnRateFast",
        trigger_hint="Melange erreurs et lenteurs.",
    ),
]


def catalog_payload() -> list[dict]:
    return [asdict(item) for item in ALERT_SCENARIOS]


def _log_event(level: str, message: str, **fields) -> None:
    extra = {"event": message, **fields}
    getattr(log, level)(message, extra=extra)


def trigger_scenario(scenario_id: str, metrics: dict) -> dict:
    scenario = next((item for item in ALERT_SCENARIOS if item.id == scenario_id), None)
    if scenario is None:
        raise ValueError(f"Unknown scenario: {scenario_id}")

    handlers = {
        "errors": _trigger_errors,
        "payment": _trigger_payment,
        "database": _trigger_database,
        "404": _trigger_404,
        "latency": _trigger_latency,
        "slow-post": _trigger_slow_post,
        "queue": _trigger_queue,
        "in-flight": _trigger_in_flight,
        "cache": _trigger_cache,
        "traffic": _trigger_traffic,
        "slo-burn": _trigger_slo_burn,
    }

    result = handlers[scenario_id](metrics)
    _log_event(
        "warning",
        "alert_scenario_triggered",
        scenario_id=scenario_id,
        alert=scenario.prometheus_alert,
        **result,
    )
    return {
        "scenario": asdict(scenario),
        "result": result,
        "message": f"Scenario '{scenario.name}' declenche. Verifie Prometheus/Alertmanager dans 1-2 min.",
    }


def _trigger_errors(metrics: dict) -> dict:
    req_count = metrics["REQ_COUNT"]
    db_errors = metrics["DB_ERRORS"]
    count = 40
    for _ in range(count):
        req_count.labels(method="GET", route="list_orders", status="500").inc()
        db_errors.labels(operation="select").inc()
    return {"errors_generated": count}


def _trigger_payment(metrics: dict) -> dict:
    payment_errors = metrics["PAYMENT_ERRORS"]
    orders_total = metrics["ORDERS_TOTAL"]
    count = 25
    for i in range(count):
        reason = "declined" if i % 2 == 0 else "timeout"
        payment_errors.labels(reason=reason).inc()
        orders_total.labels(status="failed").inc()
    return {"payment_errors_generated": count}


def _trigger_database(metrics: dict) -> dict:
    db_errors = metrics["DB_ERRORS"]
    req_count = metrics["REQ_COUNT"]
    count = 20
    for i in range(count):
        operation = "select" if i % 2 == 0 else "delete"
        db_errors.labels(operation=operation).inc()
        req_count.labels(method="GET", route="list_orders", status="500").inc()
    return {"db_errors_generated": count}


def _trigger_404(metrics: dict) -> dict:
    req_count = metrics["REQ_COUNT"]
    count = 60
    for _ in range(count):
        req_count.labels(method="GET", route="get_order", status="404").inc()
    return {"not_found_generated": count}


def _trigger_latency(metrics: dict) -> dict:
    latency = metrics["REQ_LATENCY"]
    count = 20
    for _ in range(count):
        latency.labels(method="GET", route="list_orders").observe(random.uniform(0.55, 1.5))
        metrics["REQ_COUNT"].labels(method="GET", route="list_orders", status="200").inc()
    return {"slow_reads_generated": count}


def _trigger_slow_post(metrics: dict) -> dict:
    latency = metrics["REQ_LATENCY"]
    count = 15
    for _ in range(count):
        latency.labels(method="POST", route="place_order").observe(random.uniform(0.35, 0.9))
        metrics["REQ_COUNT"].labels(method="POST", route="place_order", status="201").inc()
    return {"slow_posts_generated": count}


def _trigger_queue(metrics: dict) -> dict:
    queue_depth = metrics["QUEUE_DEPTH"]
    value = random.randint(35, 55)
    queue_depth.set(value)
    return {"queue_depth_set": value}


def _trigger_in_flight(metrics: dict) -> dict:
    in_flight = metrics["ORDERS_IN_FLIGHT"]
    value = random.randint(6, 12)
    in_flight.set(value)
    return {"in_flight_set": value, "note": "La valeur redescendra au prochain POST termine."}


def _trigger_cache(metrics: dict) -> dict:
    cache_miss = metrics["CACHE_MISS"]
    count = 80
    for _ in range(count):
        cache_miss.inc()
    return {"cache_misses_generated": count}


def _trigger_traffic(metrics: dict) -> dict:
    req_count = metrics["REQ_COUNT"]
    orders_total = metrics["ORDERS_TOTAL"]
    count = 120
    for _ in range(count):
        req_count.labels(method="POST", route="place_order", status="201").inc()
        orders_total.labels(status="created").inc()
    return {"orders_created_burst": count}


def _trigger_slo_burn(metrics: dict) -> dict:
    errors = _trigger_errors(metrics)
    latency = _trigger_latency(metrics)
    return {"errors": errors, "latency": latency}
