"""
echo-svc: a tiny FastAPI service I use as the workload for the self-healing
k8s demo. It does three things and nothing else:

  GET /          -> echoes back request metadata (proves traffic is flowing)
  GET /health    -> liveness: "am I alive at all?"  (cheap, never touches deps)
  GET /ready     -> readiness: "should I get traffic yet?" (gated on warmup)

The split between /health and /ready is deliberate and it's the whole point of
the demo. In the EKS incident that this repo mirrors, our probes were wrong:
the liveness probe was effectively doing readiness work, so the moment a pod
got slow under memory pressure the kubelet killed it instead of just pulling it
out of rotation. That turned a recoverable blip into a CrashLoopBackOff storm.

So here:
  - /health stays dirt cheap and always answers fast once the process is up.
  - /ready flips to true only after a short warmup, and can be forced to fail
    via FAIL_READY=1 so I can demonstrate "pod stays up but stops taking
    traffic" without killing anything.

Also exposes Prometheus metrics at /metrics so the observability stack has
something real to scrape.
"""

import os
import time
import socket

from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse
from prometheus_client import (
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

APP_NAME = os.getenv("APP_NAME", "echo-svc")
# Warmup window before /ready reports healthy. Kept short for the demo; in the
# real world this maps to cache priming / connection pool warmup.
READY_AFTER_SECONDS = float(os.getenv("READY_AFTER_SECONDS", "5"))
# Escape hatch for the runbook: force readiness to fail on demand.
FAIL_READY = os.getenv("FAIL_READY", "0") == "1"

START_TIME = time.monotonic()
HOSTNAME = socket.gethostname()

app = FastAPI(title=APP_NAME, version="1.0.0")

# Use a dedicated registry rather than the global default. It keeps the process
# clean, and it means reloading this module (which the tests do, to pick up env
# changes per-test) gets a fresh registry instead of re-registering the same
# collectors on the global default and blowing up with "Duplicated timeseries".
REGISTRY = CollectorRegistry()
REQUESTS = Counter(
    "echo_requests_total",
    "Total HTTP requests handled by echo-svc",
    ["path", "method", "status"],
    registry=REGISTRY,
)
LATENCY = Histogram(
    "echo_request_duration_seconds",
    "Request latency in seconds",
    ["path"],
    registry=REGISTRY,
)


def _uptime() -> float:
    return round(time.monotonic() - START_TIME, 3)


@app.get("/")
def root():
    with LATENCY.labels(path="/").time():
        body = {
            "app": APP_NAME,
            "pod": HOSTNAME,
            "uptime_seconds": _uptime(),
            "message": "echo ok",
        }
    REQUESTS.labels(path="/", method="GET", status="200").inc()
    return JSONResponse(body)


@app.get("/health")
def health():
    # Liveness. Intentionally trivial: if the event loop is running, we are
    # alive. Do NOT add dependency checks here - that mistake is exactly what
    # caused the kubelet to kill healthy-but-slow pods during the stampede.
    REQUESTS.labels(path="/health", method="GET", status="200").inc()
    return {"status": "alive", "pod": HOSTNAME, "uptime_seconds": _uptime()}


@app.get("/ready")
def ready():
    # Readiness. This is allowed to say "not yet" without anyone getting killed.
    warmed = _uptime() >= READY_AFTER_SECONDS
    ok = warmed and not FAIL_READY
    status = "200" if ok else "503"
    REQUESTS.labels(path="/ready", method="GET", status=status).inc()
    payload = {
        "status": "ready" if ok else "not-ready",
        "pod": HOSTNAME,
        "warmed_up": warmed,
        "fail_ready_flag": FAIL_READY,
        "uptime_seconds": _uptime(),
    }
    return JSONResponse(payload, status_code=200 if ok else 503)


@app.get("/metrics")
def metrics():
    return Response(generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)
