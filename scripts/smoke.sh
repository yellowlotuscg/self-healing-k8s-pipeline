#!/usr/bin/env bash
# Smoke test against the deployed service. Port-forwards the Service and checks
# that /, /health, and /ready all answer correctly. Used by `make smoke` and by
# the CI workflow after loading the image into kind.
set -euo pipefail

NS="${NS:-echo}"
SVC="${SVC:-echo-svc}"
LOCAL_PORT="${LOCAL_PORT:-18080}"

echo ">> waiting for rollout"
kubectl -n "${NS}" rollout status "deploy/${SVC}" --timeout=120s

echo ">> port-forwarding svc/${SVC} ${LOCAL_PORT}->80"
kubectl -n "${NS}" port-forward "svc/${SVC}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
# Always clean up the port-forward, even on failure.
trap 'kill "${PF_PID}" >/dev/null 2>&1 || true' EXIT
sleep 4

base="http://127.0.0.1:${LOCAL_PORT}"
fail=0

check() {
  local path="$1" want="$2"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "${base}${path}")"
  if [[ "${code}" == "${want}" ]]; then
    echo "   OK   ${path} -> ${code}"
  else
    echo "   FAIL ${path} -> ${code} (wanted ${want})"
    fail=1
  fi
}

echo ">> checking endpoints"
check "/"       200
check "/health" 200
check "/ready"  200

if [[ "${fail}" -ne 0 ]]; then
  echo ">> SMOKE FAILED"
  exit 1
fi
echo ">> SMOKE PASSED"
