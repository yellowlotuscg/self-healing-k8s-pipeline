"""
Tests for echo-svc. These run in CI (GitHub Actions + Jenkins) before any image
gets built. They're small on purpose - I care about the probe contract more
than coverage numbers, because the probe contract is what bit us in prod.
"""

import importlib
import os

from fastapi.testclient import TestClient


def _client(**env):
    # Reload the module under fresh env so READY_AFTER_SECONDS / FAIL_READY
    # take effect per-test.
    for k, v in env.items():
        os.environ[k] = v
    import app.main as m  # noqa: WPS433
    importlib.reload(m)
    return TestClient(m.app), m


def test_health_is_always_alive():
    client, _ = _client(READY_AFTER_SECONDS="0")
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "alive"


def test_ready_true_after_warmup():
    client, _ = _client(READY_AFTER_SECONDS="0", FAIL_READY="0")
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_ready_can_be_forced_to_fail():
    # This backs the runbook "break readiness without killing the pod" step.
    client, _ = _client(READY_AFTER_SECONDS="0", FAIL_READY="1")
    r = client.get("/ready")
    assert r.status_code == 503
    assert r.json()["status"] == "not-ready"


def test_root_echoes():
    client, _ = _client(READY_AFTER_SECONDS="0")
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["message"] == "echo ok"


def test_metrics_exposed():
    client, _ = _client(READY_AFTER_SECONDS="0")
    r = client.get("/metrics")
    assert r.status_code == 200
    assert b"echo_requests_total" in r.content
