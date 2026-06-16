import os
import random
import time
import uuid

from alerts import ALERT_SCENARIOS, catalog_payload, trigger_scenario
from flask import Flask, Response, jsonify, render_template, request
from log_buffer import format_sse, setup_logging, snapshot, subscribe, unsubscribe
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    Info,
    generate_latest,
)

app = Flask(__name__)
log = setup_logging()

REQ_COUNT = Counter(
    "http_requests_total",
    "HTTP requests served by the orders API.",
    ["method", "route", "status"],
)

REQ_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds for the orders API.",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)

ORDERS_IN_FLIGHT = Gauge(
    "orders_in_flight",
    "Number of orders currently being processed.",
)

ORDERS_TOTAL = Counter(
    "orders_total",
    "Total orders by final status.",
    ["status"],
)

PAYMENT_ERRORS = Counter(
    "payment_errors_total",
    "Total payment processing errors.",
    ["reason"],
)

DB_ERRORS = Counter(
    "db_errors_total",
    "Total database errors.",
    ["operation"],
)

QUEUE_DEPTH = Gauge(
    "orders_queue_depth",
    "Simulated depth of the orders processing queue.",
)

CACHE_HIT = Counter(
    "cache_hits_total",
    "Cache hits on order lookups.",
)

CACHE_MISS = Counter(
    "cache_misses_total",
    "Cache misses on order lookups.",
)

APP_INFO = Info(
    "orders_app",
    "Static metadata about the orders service.",
)
APP_INFO.info({"version": "lab03", "env": "demo", "region": "eu-west-1"})

METRICS = {
    "REQ_COUNT": REQ_COUNT,
    "REQ_LATENCY": REQ_LATENCY,
    "ORDERS_IN_FLIGHT": ORDERS_IN_FLIGHT,
    "ORDERS_TOTAL": ORDERS_TOTAL,
    "PAYMENT_ERRORS": PAYMENT_ERRORS,
    "DB_ERRORS": DB_ERRORS,
    "QUEUE_DEPTH": QUEUE_DEPTH,
    "CACHE_HIT": CACHE_HIT,
    "CACHE_MISS": CACHE_MISS,
}


def _simulate_queue() -> None:
    depth = max(0, random.gauss(15, 8))
    QUEUE_DEPTH.set(round(depth))


@app.before_request
def _start_timer() -> None:
    request._start = time.perf_counter()
    request.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    traceparent = request.headers.get("traceparent", "")
    if traceparent and "-" in traceparent:
        parts = traceparent.split("-")
        request.trace_id = parts[1] if len(parts) >= 2 else ""
    else:
        request.trace_id = ""
    _simulate_queue()


@app.after_request
def _record_metrics(resp: Response) -> Response:
    if request.endpoint in {"metrics", "stream_logs"}:
        return resp

    elapsed = time.perf_counter() - getattr(request, "_start", time.perf_counter())
    route = request.endpoint or "unknown"
    status = str(resp.status_code)

    REQ_COUNT.labels(method=request.method, route=route, status=status).inc()
    REQ_LATENCY.labels(method=request.method, route=route).observe(elapsed)

    log.info(
        "request_completed",
        extra={
            "event": "request_completed",
            "method": request.method,
            "route": route,
            "status": resp.status_code,
            "elapsed_ms": round(elapsed * 1000, 2),
            "request_id": request.request_id,
            "trace_id": request.trace_id,
        },
    )
    resp.headers["X-Request-ID"] = request.request_id
    return resp


@app.route("/")
def dashboard() -> str:
    return render_template("index.html")


@app.route("/api/alerts")
def list_alerts():
    return jsonify(catalog_payload())


@app.route("/api/trigger/<scenario_id>", methods=["POST"])
def trigger_alert_scenario(scenario_id: str):
    try:
        payload = trigger_scenario(scenario_id, METRICS)
        return jsonify(payload)
    except ValueError as exc:
        return jsonify(error=str(exc)), 404


@app.route("/api/logs")
def list_logs():
    return jsonify(snapshot())


@app.route("/api/logs/stream")
def stream_logs():
    def generate():
        for entry in snapshot():
            yield format_sse(entry)

        subscriber = subscribe()
        try:
            while True:
                entry = subscriber.get()
                yield format_sse(entry)
        finally:
            unsubscribe(subscriber)

    return Response(
        generate(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.route("/orders", methods=["GET"])
def list_orders():
    if random.random() < 0.3:
        CACHE_HIT.inc()
    else:
        CACHE_MISS.inc()

    delay = random.uniform(0.01, 0.150)
    if random.random() < 0.08:
        delay = random.uniform(0.4, 1.2)
    time.sleep(delay)

    if random.random() < 0.05:
        DB_ERRORS.labels(operation="select").inc()
        return jsonify(error="db unreachable"), 500

    return jsonify(orders=[{"id": 1}, {"id": 2}, {"id": 3}])


@app.route("/orders", methods=["POST"])
def place_order():
    ORDERS_IN_FLIGHT.inc()
    try:
        delay = random.uniform(0.02, 0.300)
        if random.random() < 0.06:
            delay = random.uniform(0.5, 2.0)
        time.sleep(delay)

        if random.random() < 0.05:
            PAYMENT_ERRORS.labels(reason="declined").inc()
            ORDERS_TOTAL.labels(status="failed").inc()
            return jsonify(error="payment declined"), 500

        if random.random() < 0.02:
            PAYMENT_ERRORS.labels(reason="timeout").inc()
            ORDERS_TOTAL.labels(status="failed").inc()
            return jsonify(error="payment timeout"), 503

        ORDERS_TOTAL.labels(status="created").inc()
        return jsonify(order={"id": str(uuid.uuid4())[:8]}), 201
    finally:
        ORDERS_IN_FLIGHT.dec()


@app.route("/orders/<order_id>", methods=["GET"])
def get_order(order_id: str):
    time.sleep(random.uniform(0.005, 0.05))
    if random.random() < 0.1:
        return jsonify(error="not found"), 404
    return jsonify(
        order={"id": order_id, "status": random.choice(["pending", "shipped", "delivered"])}
    )


@app.route("/orders/<order_id>", methods=["DELETE"])
def cancel_order(order_id: str):
    time.sleep(random.uniform(0.01, 0.08))
    if random.random() < 0.03:
        DB_ERRORS.labels(operation="delete").inc()
        return jsonify(error="db error"), 500
    ORDERS_TOTAL.labels(status="cancelled").inc()
    return jsonify(cancelled=True)


@app.route("/healthz")
def healthz():
    return "ok", 200


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
