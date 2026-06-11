# CCF Helm chart - local development & observability helpers
#
# Quick start (one command):
#   make up        # create cluster + install CCF
#   make pf        # port-forward UI (8000) and API (8080)
#
# With observability (Loki + Prometheus + Grafana Alloy):
#   make up-obs
#
# Tear everything down:
#   make down

CLUSTER_NAME ?= ccf
NAMESPACE    ?= ccf
OBS_NAMESPACE ?= observability
RELEASE      ?= ccf
CHART_DIR    ?= .

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

## ---------------------------------------------------------------- bootstrap
.PHONY: up
up: check-tools kind-ensure install-local ## One-shot: cluster + install CCF (then `make pf`)
	@$(MAKE) --no-print-directory status
	@echo ""
	@echo "CCF is up. Expose it locally with:  make pf"
	@echo "Then open http://localhost:8000"

.PHONY: up-obs
up-obs: up obs-stack obs-alloy ## Bootstrap CCF + observability (Loki/Prometheus/Alloy)
	@echo "Observability installed in namespace '$(OBS_NAMESPACE)'."

.PHONY: down
down: ## Tear everything down (release + kind cluster)
	-helm uninstall $(RELEASE) --namespace $(NAMESPACE)
	-$(MAKE) --no-print-directory kind-down

.PHONY: check-tools
check-tools: ## Verify required CLIs are installed
	@for t in kind kubectl helm; do \
		command -v $$t >/dev/null 2>&1 || { echo "ERROR: '$$t' not found in PATH"; exit 1; }; \
	done
	@echo "tools OK: kind, kubectl, helm"

## ---------------------------------------------------------------- local cluster
.PHONY: kind-up
kind-up: ## Create a local kind cluster
	kind create cluster --name $(CLUSTER_NAME) --config local/kind-config.yaml

.PHONY: kind-ensure
kind-ensure: ## Create the kind cluster only if it does not exist
	@if kind get clusters 2>/dev/null | grep -qx "$(CLUSTER_NAME)"; then \
		echo "kind cluster '$(CLUSTER_NAME)' already exists"; \
	else \
		kind create cluster --name $(CLUSTER_NAME) --config local/kind-config.yaml; \
	fi

.PHONY: kind-down
kind-down: ## Delete the local kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

## ---------------------------------------------------------------- CCF (local)
.PHONY: lint
lint: ## helm lint umbrella + subcharts
	helm lint $(CHART_DIR)
	helm lint $(CHART_DIR)/charts/ccf-app
	helm lint $(CHART_DIR)/charts/ccf-agent

.PHONY: template-local
template-local: ## Render umbrella manifests with local values
	helm template $(RELEASE) $(CHART_DIR) -f values-local.yaml

.PHONY: install-local
install-local: ## Install/upgrade the full stack (umbrella) with local values
	helm upgrade --install $(RELEASE) $(CHART_DIR) \
		--namespace $(NAMESPACE) --create-namespace \
		-f values-local.yaml --wait --timeout 5m

.PHONY: install-app
install-app: ## Install ccf-app standalone (production values)
	helm upgrade --install ccf-app $(CHART_DIR)/charts/ccf-app \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(CHART_DIR)/charts/ccf-app/values-production.yaml

.PHONY: install-agent
install-agent: ## Install ccf-agent standalone (production values)
	helm upgrade --install ccf-agent $(CHART_DIR)/charts/ccf-agent \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(CHART_DIR)/charts/ccf-agent/values-production.yaml

.PHONY: uninstall
uninstall: ## Uninstall the umbrella release
	helm uninstall $(RELEASE) --namespace $(NAMESPACE)

.PHONY: status
status: ## Show CCF pods
	kubectl get pods,svc -n $(NAMESPACE)

## ---------------------------------------------------------------- port-forward
.PHONY: pf
pf: ## Port-forward UI (8000) and API (8080)
	@echo "UI  -> http://localhost:8000"
	@echo "API -> http://localhost:8080"
	@trap 'kill 0' EXIT; \
	kubectl -n $(NAMESPACE) port-forward svc/$(RELEASE)-ui 8000:80 & \
	kubectl -n $(NAMESPACE) port-forward svc/$(RELEASE)-api 8080:8080 & \
	wait

## ---------------------------------------------------------------- observability
.PHONY: obs-repos
obs-repos: ## Add Grafana/Prometheus helm repos
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update

.PHONY: obs-stack
obs-stack: obs-repos ## Install a minimal Loki + Prometheus stack for local testing
	helm upgrade --install loki grafana/loki \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		--set deploymentMode=SingleBinary \
		--set loki.commonConfig.replication_factor=1 \
		--set loki.storage.type=filesystem \
		--set loki.auth_enabled=false \
		--set singleBinary.replicas=1 \
		--set read.replicas=0 --set write.replicas=0 --set backend.replicas=0 \
		--set chunksCache.enabled=false --set resultsCache.enabled=false
	helm upgrade --install prometheus prometheus-community/prometheus \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		--set server.extraFlags="{web.enable-remote-write-receiver}" \
		--set alertmanager.enabled=false \
		--set prometheus-pushgateway.enabled=false

.PHONY: obs-alloy
obs-alloy: obs-repos ## Install Grafana Alloy to collect CCF logs & metrics
	helm upgrade --install ccf-alloy grafana/alloy \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		-f observability/alloy-values.yaml

.PHONY: obs-grafana
obs-grafana: ## Port-forward Grafana (admin/admin if installed via obs-stack)
	kubectl -n $(OBS_NAMESPACE) port-forward svc/loki 3100:3100
