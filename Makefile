# CCF Helm chart - local development & observability helpers
#
# Two local Kubernetes runtimes are supported via the RUNTIME variable:
#   RUNTIME=kind    (default) -> creates/uses a local `kind` cluster
#   RUNTIME=docker            -> uses Docker Desktop's built-in Kubernetes
#
# Quick start (kind, the default):
#   make up         # create cluster + install CCF
#   make pf         # port-forward UI (8000) and API (8080)
#
# Quick start (Docker Desktop Kubernetes):
#   make up-docker  # verify docker-desktop context + install CCF
#   make pf-docker  # port-forward against docker-desktop
#
# With observability (Loki + Prometheus + Grafana Alloy):
#   make up-obs                 # kind
#   make RUNTIME=docker up-obs  # Docker Desktop
#
# Tear everything down:
#   make down         # kind: uninstall + delete cluster
#   make down-docker  # docker: uninstall release (cluster stays)

CLUSTER_NAME  ?= ccf
NAMESPACE     ?= ccf
OBS_NAMESPACE ?= observability
RELEASE       ?= ccf
CHART_DIR     ?= .

# ---------------------------------------------------------------- runtime
# RUNTIME selects the local Kubernetes target: `kind` or `docker`.
RUNTIME ?= kind

ifeq ($(RUNTIME),docker)
KUBE_CONTEXT ?= docker-desktop
else
KUBE_CONTEXT ?= kind-$(CLUSTER_NAME)
endif

# Pin every helm/kubectl call to the selected cluster so we never deploy to the
# wrong context by accident.
HELM_CTX := --kube-context $(KUBE_CONTEXT)
KUBECTL  := kubectl --context $(KUBE_CONTEXT)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Active runtime: RUNTIME=$(RUNTIME)  (context: $(KUBE_CONTEXT))"

## ---------------------------------------------------------------- bootstrap
.PHONY: up
up: check-tools cluster-ensure install-local ## One-shot: cluster + install CCF (then `make pf`)
	@$(MAKE) --no-print-directory status
	@echo ""
	@echo "CCF is up on '$(KUBE_CONTEXT)'. Expose it locally with:  make pf"
	@echo "Then open http://localhost:8000"

.PHONY: up-docker
up-docker: ## One-shot on Docker Desktop Kubernetes (context: docker-desktop)
	@$(MAKE) RUNTIME=docker up

.PHONY: up-obs
up-obs: up obs-stack obs-alloy ## Bootstrap CCF + observability (Loki/Prometheus/Alloy)
	@echo "Observability installed in namespace '$(OBS_NAMESPACE)'."

.PHONY: down
down: ## Tear down (uninstall release; kind: also delete the cluster)
	-helm uninstall $(RELEASE) --namespace $(NAMESPACE) $(HELM_CTX)
ifeq ($(RUNTIME),docker)
	@echo "Docker Desktop cluster left running. Disable Kubernetes in Docker Desktop to stop it."
else
	-$(MAKE) --no-print-directory kind-down
endif

.PHONY: down-docker
down-docker: ## Uninstall the CCF release from Docker Desktop Kubernetes
	@$(MAKE) RUNTIME=docker down

.PHONY: check-tools
check-tools: ## Verify required CLIs are installed for the active runtime
	@for t in kubectl helm; do \
		command -v $$t >/dev/null 2>&1 || { echo "ERROR: '$$t' not found in PATH"; exit 1; }; \
	done
ifeq ($(RUNTIME),docker)
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: 'docker' not found in PATH"; exit 1; }
	@echo "tools OK: docker, kubectl, helm"
else
	@command -v kind >/dev/null 2>&1 || { echo "ERROR: 'kind' not found in PATH"; exit 1; }
	@echo "tools OK: kind, kubectl, helm"
endif

## ---------------------------------------------------------------- local cluster
.PHONY: cluster-ensure
cluster-ensure: ## Ensure the target cluster exists (kind: create; docker: verify)
ifeq ($(RUNTIME),docker)
	@$(MAKE) --no-print-directory docker-ensure
else
	@$(MAKE) --no-print-directory kind-ensure
endif

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

.PHONY: docker-ensure
docker-ensure: ## Verify Docker Desktop Kubernetes is enabled and reachable
	@kubectl config get-contexts docker-desktop >/dev/null 2>&1 || { \
		echo "ERROR: kube-context 'docker-desktop' not found."; \
		echo "Enable it in Docker Desktop: Settings > Kubernetes > Enable Kubernetes."; \
		exit 1; }
	@$(KUBECTL) cluster-info >/dev/null 2>&1 || { \
		echo "ERROR: cannot reach the 'docker-desktop' cluster."; \
		echo "Make sure Docker Desktop is running with Kubernetes enabled."; \
		exit 1; }
	@echo "Docker Desktop Kubernetes is reachable (context: docker-desktop)"

## ---------------------------------------------------------------- CCF (local)
.PHONY: deps
deps: ## Build umbrella chart dependencies (vendored subchart .tgz)
	helm dependency build $(CHART_DIR)

.PHONY: lint
lint: ## helm lint umbrella + subcharts
	helm lint $(CHART_DIR)
	helm lint $(CHART_DIR)/charts/ccf-app
	helm lint $(CHART_DIR)/charts/ccf-agent

.PHONY: template-local
template-local: deps ## Render umbrella manifests with local values
	helm template $(RELEASE) $(CHART_DIR) -f values-local.yaml

.PHONY: install-local
install-local: deps ## Install/upgrade the full stack (umbrella) with local values
	helm upgrade --install $(RELEASE) $(CHART_DIR) $(HELM_CTX) \
		--namespace $(NAMESPACE) --create-namespace \
		-f values-local.yaml --wait --timeout 5m

.PHONY: install-aks
install-aks: deps ## Install CCF on the CURRENT kube-context (e.g. AKS) with values-aks.yaml
	helm upgrade --install $(RELEASE) $(CHART_DIR) \
		--namespace $(NAMESPACE) --create-namespace \
		-f values-aks.yaml --wait --timeout 8m

.PHONY: install-app
install-app: deps ## Install ccf-app standalone (production values)
	helm upgrade --install ccf-app $(CHART_DIR)/charts/ccf-app $(HELM_CTX) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(CHART_DIR)/charts/ccf-app/values-production.yaml

.PHONY: install-agent
install-agent: ## Install ccf-agent standalone (production values)
	helm upgrade --install ccf-agent $(CHART_DIR)/charts/ccf-agent $(HELM_CTX) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(CHART_DIR)/charts/ccf-agent/values-production.yaml

.PHONY: uninstall
uninstall: ## Uninstall the umbrella release
	helm uninstall $(RELEASE) --namespace $(NAMESPACE) $(HELM_CTX)

.PHONY: status
status: ## Show CCF pods and services
	$(KUBECTL) get pods,svc -n $(NAMESPACE)

## ---------------------------------------------------------------- port-forward
.PHONY: pf
pf: ## Port-forward UI (8000) and API (8080)
	@echo "Context: $(KUBE_CONTEXT)"
	@echo "UI  -> http://localhost:8000"
	@echo "API -> http://localhost:8080"
	@trap 'kill 0' EXIT; \
	$(KUBECTL) -n $(NAMESPACE) port-forward svc/$(RELEASE)-ui 8000:80 & \
	$(KUBECTL) -n $(NAMESPACE) port-forward svc/$(RELEASE)-api 8080:8080 & \
	wait

.PHONY: pf-docker
pf-docker: ## Port-forward UI/API against Docker Desktop Kubernetes
	@$(MAKE) RUNTIME=docker pf

## ---------------------------------------------------------------- observability
.PHONY: obs-repos
obs-repos: ## Add Grafana/Prometheus helm repos
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update

.PHONY: obs-stack
obs-stack: obs-repos ## Install a minimal Loki + Prometheus stack for local testing
	helm upgrade --install loki grafana/loki $(HELM_CTX) \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		--set deploymentMode=SingleBinary \
		--set loki.commonConfig.replication_factor=1 \
		--set loki.storage.type=filesystem \
		--set loki.auth_enabled=false \
		--set singleBinary.replicas=1 \
		--set read.replicas=0 --set write.replicas=0 --set backend.replicas=0 \
		--set chunksCache.enabled=false --set resultsCache.enabled=false
	helm upgrade --install prometheus prometheus-community/prometheus $(HELM_CTX) \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		--set server.extraFlags="{web.enable-remote-write-receiver}" \
		--set alertmanager.enabled=false \
		--set prometheus-pushgateway.enabled=false

.PHONY: obs-alloy
obs-alloy: obs-repos ## Install Grafana Alloy to collect CCF logs & metrics
	helm upgrade --install ccf-alloy grafana/alloy $(HELM_CTX) \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		-f observability/alloy-values.yaml

.PHONY: obs-grafana
obs-grafana: ## Port-forward Loki (3100) for local querying
	$(KUBECTL) -n $(OBS_NAMESPACE) port-forward svc/loki 3100:3100
