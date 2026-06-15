#!/usr/bin/env bash
# Build the echo-svc image and load it into the kind cluster's node so the
# Deployment's imagePullPolicy: IfNotPresent finds it without a registry.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-self-healing-demo}"
IMAGE="${IMAGE:-echo-svc:local}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ">> building ${IMAGE}"
docker build -t "${IMAGE}" "${REPO_ROOT}/app"

echo ">> loading ${IMAGE} into kind cluster '${CLUSTER_NAME}'"
kind load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"

echo ">> done. image is available to pods as ${IMAGE}"
