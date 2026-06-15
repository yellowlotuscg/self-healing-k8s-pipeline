# Self-healing k8s demo - operator entrypoints.
# `make help` lists everything. The only target that runs without Docker/kind
# is `make validate` (static YAML + client-side dry-run).

SHELL := /usr/bin/env bash
CLUSTER_NAME ?= self-healing-demo
IMAGE ?= echo-svc:local
MONITORING_NS ?= monitoring

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: cluster-up
cluster-up: ## Create the local kind cluster (3 nodes) + ingress-nginx
	kind create cluster --name $(CLUSTER_NAME) --config scripts/kind-config.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx \
		--for=condition=Ready pod \
		--selector=app.kubernetes.io/component=controller --timeout=180s

.PHONY: build-load
build-load: ## Build the app image and load it into kind
	CLUSTER_NAME=$(CLUSTER_NAME) IMAGE=$(IMAGE) bash scripts/load-image.sh

.PHONY: deploy
deploy: build-load ## Deploy the GOOD (fixed) manifests
	kubectl apply -f k8s/
	kubectl apply -f ci/jenkins-pvc.yaml
	kubectl -n echo rollout status deploy/echo-svc --timeout=120s

.PHONY: observability
observability: ## Install kube-prometheus-stack + app ServiceMonitor/alerts/dashboard
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install kube-prometheus-stack \
		prometheus-community/kube-prometheus-stack \
		-n $(MONITORING_NS) --create-namespace \
		-f observability/values-kube-prometheus-stack.yaml --wait
	kubectl apply -f observability/servicemonitor.yaml
	kubectl apply -f observability/prometheus-rules.yaml
	NS=$(MONITORING_NS) bash scripts/grafana-dashboard-configmap.sh

.PHONY: break
break: ## Apply the BAD variant to reproduce the stampede
	@echo ">> applying the broken deployment - watch it misbehave with: kubectl -n echo get pods -w"
	kubectl apply -f k8s/incident/deployment-bad.yaml

.PHONY: heal
heal: ## Re-apply the GOOD manifests to recover
	kubectl apply -f k8s/deployment.yaml
	kubectl -n echo rollout status deploy/echo-svc --timeout=120s

.PHONY: smoke
smoke: ## Port-forward and curl /, /health, /ready
	bash scripts/smoke.sh

.PHONY: validate
validate: ## Static validation - NO cluster needed (YAML parse + client dry-run)
	bash scripts/validate.sh

.PHONY: cluster-down
cluster-down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)
