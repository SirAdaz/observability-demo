from __future__ import annotations

import json
import logging
import queue
import threading
from collections import deque
from datetime import datetime, timezone
from typing import Any

from pythonjsonlogger import jsonlogger

LOG_BUFFER_SIZE = 500

_log_buffer: deque[dict[str, Any]] = deque(maxlen=LOG_BUFFER_SIZE)
_log_lock = threading.Lock()
_subscribers: list[queue.Queue[dict[str, Any]]] = []

_EXTRA_FIELDS = (
    "event",
    "method",
    "route",
    "status",
    "elapsed_ms",
    "request_id",
    "trace_id",
    "scenario_id",
    "alert",
    "errors_generated",
    "payment_errors_generated",
    "db_errors_generated",
    "not_found_generated",
    "slow_reads_generated",
    "slow_posts_generated",
    "queue_depth_set",
    "in_flight_set",
    "cache_misses_generated",
    "orders_created_burst",
)


class RingBufferHandler(logging.Handler):
    def emit(self, record: logging.LogRecord) -> None:
        entry = _record_to_entry(record)
        with _log_lock:
            _log_buffer.append(entry)
            for subscriber in _subscribers:
                subscriber.put(entry)


class JsonStdoutFormatter(jsonlogger.JsonFormatter):
    def add_fields(
        self,
        log_record: dict[str, Any],
        record: logging.LogRecord,
        message_dict: dict[str, Any],
    ) -> None:
        super().add_fields(log_record, record, message_dict)
        log_record["service"] = "orders"
        log_record["timestamp"] = datetime.fromtimestamp(
            record.created, tz=timezone.utc
        ).isoformat()
        for key in _EXTRA_FIELDS:
            value = getattr(record, key, None)
            if value is not None:
                log_record[key] = value


def _record_to_entry(record: logging.LogRecord) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
        "level": record.levelname,
        "message": record.getMessage(),
        "service": "orders",
    }

    for key in _EXTRA_FIELDS:
        value = getattr(record, key, None)
        if value is not None:
            payload[key] = value

    return payload


def setup_logging() -> logging.Logger:
    logger = logging.getLogger("orders")
    logger.handlers.clear()
    logger.setLevel(logging.INFO)
    logger.propagate = False

    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(
        JsonStdoutFormatter("%(timestamp)s %(levelname)s %(name)s %(message)s")
    )

    buffer_handler = RingBufferHandler()
    logger.addHandler(stream_handler)
    logger.addHandler(buffer_handler)
    return logger


def snapshot() -> list[dict[str, Any]]:
    with _log_lock:
        return list(_log_buffer)


def subscribe() -> queue.Queue[dict[str, Any]]:
    subscriber: queue.Queue[dict[str, Any]] = queue.Queue()
    with _log_lock:
        _subscribers.append(subscriber)
    return subscriber


def unsubscribe(subscriber: queue.Queue[dict[str, Any]]) -> None:
    with _log_lock:
        if subscriber in _subscribers:
            _subscribers.remove(subscriber)


def format_sse(entry: dict[str, Any]) -> str:
    return f"data: {json.dumps(entry, ensure_ascii=False)}\n\n"
