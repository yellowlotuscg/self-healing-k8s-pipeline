#!/usr/bin/env bash
# Static validation that needs NO running cluster. This is what `make validate`
# runs and what I run before every commit. Two passes:
#   1) Every YAML file actually parses (python yaml.safe_load_all).
#   2) Plain k8s manifests validate against upstream schemas with kubeconform
#      (fully offline - no API server contact, unlike `kubectl --dry-run=client`,
#      which still reaches out for the API group list). CRD-based manifests
#      (ServiceMonitor/PrometheusRule) need the operator CRDs for full schema
#      validation, so we only assert they parse - and say so.
#
# kubeconform install (one-time): https://github.com/yannh/kubeconform
#   macOS:  brew install kubeconform   (or grab the release binary)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0

echo "== 1. YAML parse check (python yaml.safe_load_all) =="
while IFS= read -r f; do
  if python3 -c "import sys,yaml; list(yaml.safe_load_all(open(sys.argv[1])))" "$f"; then
    echo "   parse OK   ${f#"$REPO_ROOT"/}"
  else
    echo "   parse FAIL ${f#"$REPO_ROOT"/}"
    rc=1
  fi
done < <(find "$REPO_ROOT" -type f \( -name '*.yml' -o -name '*.yaml' \) -not -path '*/.git/*' | sort)

echo
echo "== 2. schema validation of plain manifests (kubeconform, offline) =="
PLAIN_MANIFESTS=(
  "$REPO_ROOT"/k8s/namespace.yaml
  "$REPO_ROOT"/k8s/configmap.yaml
  "$REPO_ROOT"/k8s/deployment.yaml
  "$REPO_ROOT"/k8s/service.yaml
  "$REPO_ROOT"/k8s/pdb.yaml
  "$REPO_ROOT"/k8s/hpa.yaml
  "$REPO_ROOT"/k8s/ingress.yaml
  "$REPO_ROOT"/k8s/incident/deployment-bad.yaml
  "$REPO_ROOT"/ci/jenkins-pvc.yaml
)
if command -v kubeconform >/dev/null 2>&1; then
  if kubeconform -strict -summary -schema-location default "${PLAIN_MANIFESTS[@]}"; then
    echo "   kubeconform OK"
  else
    echo "   kubeconform reported invalid manifests (see above)"
    rc=1
  fi
else
  echo "   kubeconform not installed - skipping schema validation."
  echo "   Install it (brew install kubeconform) for offline schema checks."
  echo "   (The YAML parse pass above still ran.)"
fi

echo
echo "== 3. CRD-based manifests (parse-only; need operator CRDs for full validation) =="
for f in \
  "$REPO_ROOT"/observability/servicemonitor.yaml \
  "$REPO_ROOT"/observability/prometheus-rules.yaml; do
  echo "   parse-only ${f#"$REPO_ROOT"/} (ServiceMonitor/PrometheusRule CRD - validated by parse above)"
done

echo
if [[ "$rc" -eq 0 ]]; then
  echo "ALL STATIC VALIDATION PASSED"
else
  echo "VALIDATION FAILURES - see above"
fi
exit "$rc"
