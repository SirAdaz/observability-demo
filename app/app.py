import logging
import os
import random
import time
import uuid

from flask import Flask, Response, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pythonjsonlogger import jsonlogger

app = Flask(__name__)

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

handler = logging.StreamHandler()
handler.setFormatter(
    jsonlogger.JsonFormatter("%(asctime)s %(levelname)s %(name)s %(message)s")
)
log = logging.getLogger("orders")
log.addHandler(handler)
log.setLevel(logging.INFO)
log.propagate = False


@app.before_request
def _start_timer():
    request._start = time.perf_counter()
    request.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    traceparent = request.headers.get("traceparent", "")
    if traceparent and "-" in traceparent:
        parts = traceparent.split("-")
        request.trace_id = parts[1] if len(parts) >= 2 else ""
    else:
        request.trace_id = ""


@app.after_request
def _record_metrics(resp):
    elapsed = time.perf_counter() - request._start
    route = request.endpoint or "unknown"
    status = str(resp.status_code)

    REQ_COUNT.labels(method=request.method, route=route, status=status).inc()
    REQ_LATENCY.labels(method=request.method, route=route).observe(elapsed)

    log.info(
        "request_completed",
        extra={
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


@app.route("/orders", methods=["GET"])
def list_orders():
    time.sleep(random.uniform(0.01, 0.150))
    if random.random() < 0.05:
        return jsonify(error="db unreachable"), 500
    return jsonify(orders=[{"id": 1}, {"id": 2}, {"id": 3}])


@app.route("/orders", methods=["POST"])
def place_order():
    time.sleep(random.uniform(0.02, 0.300))
    if random.random() < 0.05:
        return jsonify(error="payment declined"), 500
    return jsonify(order={"id": str(uuid.uuid4())[:8]}), 201


@app.route("/healthz")
def healthz():
    return "ok", 200


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
