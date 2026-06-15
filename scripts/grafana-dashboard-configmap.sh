#!/usr/bin/env bash
# Wrap the dashboard JSON in a ConfigMap labeled grafana_dashboard so the
# kube-prometheus-stack Grafana sidecar auto-imports it. Applied by
# `make observability`.
set -euo pipefail

NS="${NS:-monitoring}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JSON="${REPO_ROOT}/observability/dashboards/echo-svc-dashboard.json"

kubectl create configmap echo-svc-dashboard \
  --namespace "${NS}" \
  --from-file=echo-svc-dashboard.json="${JSON}" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml --dry-run=client \
  | kubectl apply -f -

echo ">> dashboard configmap applied to namespace ${NS}; Grafana sidecar will pick it up."
