# CCF Helm chart - local (Docker Desktop) & AKS helpers.
#
# Local demo (Docker Desktop Kubernetes):
#   make up         # install CCF on docker-desktop (+ default admin + ssh plugin)
#   make pf         # port-forward UI (8000) and API (8080)
#   open http://localhost:8000   (admin@ccf.local / Admin12345!)
#   make down       # uninstall the release (cluster stays)
#
# AKS demo:
#   az aks get-credentials --resource-group <rg> --name <aks>   # selects the context
#   make install-aks ADMIN_PASSWORD='<strong-pw>'
#   make pf-aks     # port-forward against the current (AKS) context
#
# Optional add-ons (any environment):
#   GITHUB plugin:  make up PLUGIN_VALUES="values/plugins/local-ssh.yaml values/plugins/github.yaml" \
#                     GITHUB_TOKEN=... GITHUB_ORG=...
#   HA Postgres:    make up EXTRA_VALUES="values/postgres-ha.yaml" PG_PASSWORD=...
#   Observability:  make up-obs

NAMESPACE     ?= ccf
OBS_NAMESPACE ?= observability
RELEASE       ?= ccf
CHART_DIR     ?= .

# Local Kubernetes is Docker Desktop. KUBE_CONTEXT pins every local helm/kubectl
# call so we never deploy to the wrong cluster. AKS targets use the CURRENT
# context (whatever `az aks get-credentials` selected).
KUBE_CONTEXT ?= docker-desktop
HELM_CTX     := --kube-context $(KUBE_CONTEXT)
KUBECTL      := kubectl --context $(KUBE_CONTEXT)

# ---------------------------------------------------------------- values layout
# Environment overlays live in values/, plugin overlays in values/plugins/.
# Layered: environment first, then one or more reusable plugin overlays.
ENV_LOCAL ?= values/local.yaml
ENV_AKS   ?= values/aks.yaml

# Space-separated list of plugin overlays to layer on top (override freely).
PLUGIN_VALUES ?= values/plugins/local-ssh.yaml
PLUGIN_ARGS   := $(foreach f,$(PLUGIN_VALUES),-f $(f))

# Free-form overlays layered last (e.g. values/postgres-ha.yaml).
EXTRA_VALUES ?=
EXTRA_ARGS   := $(foreach f,$(EXTRA_VALUES),-f $(f))

# Optional secrets, injected only when provided so they never land in git:
#   GITHUB_TOKEN / GITHUB_ORG  -> GitHub plugin credentials
#   PG_PASSWORD                -> official (Bitnami) Postgres password
#   ADMIN_PASSWORD             -> default UI admin (also enables the bootstrap)
SECRET_ARGS :=
ifneq ($(strip $(GITHUB_TOKEN)),)
SECRET_ARGS += --set-string ccf-agent.config.plugins.github_repos.config.token=$(GITHUB_TOKEN)
endif
ifneq ($(strip $(GITHUB_ORG)),)
SECRET_ARGS += --set-string ccf-agent.config.plugins.github_repos.config.organization=$(GITHUB_ORG)
endif
ifneq ($(strip $(PG_PASSWORD)),)
SECRET_ARGS += --set-string postgresql.auth.password=$(PG_PASSWORD)
SECRET_ARGS += --set-string ccf-app.postgres.auth.password=$(PG_PASSWORD)
endif
ifneq ($(strip $(ADMIN_PASSWORD)),)
SECRET_ARGS += --set ccf-app.api.adminUser.enabled=true
SECRET_ARGS += --set-string ccf-app.api.adminUser.password=$(ADMIN_PASSWORD)
endif

# Everything layered after the environment overlay.
OVERLAY_ARGS := $(PLUGIN_ARGS) $(EXTRA_ARGS) $(SECRET_ARGS)

# Custom Rego policies (policies/): test/bundle with opa, push with gooci.
POLICY_DIR    ?= policies
POLICY_BUNDLE ?= dist/policies-bundle.tar.gz
POLICY_IMAGE  ?= ghcr.io/your-org/ccf-custom-policies:v0.1.0
GOOCI_VERSION ?= v0.0.7

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Local context: $(KUBE_CONTEXT)   (AKS targets use the current context)"

## ---------------------------------------------------------------- local demo
.PHONY: up
up: deps docker-ensure ## Install CCF locally on Docker Desktop (then `make pf`)
	helm upgrade --install $(RELEASE) $(CHART_DIR) $(HELM_CTX) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(ENV_LOCAL) $(OVERLAY_ARGS) --wait --timeout 5m
	@$(MAKE) --no-print-directory status
	@echo ""
	@echo "CCF is up on '$(KUBE_CONTEXT)'. Expose it with:  make pf"
	@echo "Then open http://localhost:8000  (admin@ccf.local / Admin12345!)"

.PHONY: up-obs
up-obs: up obs-stack obs-alloy ## Local demo + observability (Loki/Prometheus/Alloy)
	@echo "Observability installed in namespace '$(OBS_NAMESPACE)'."

.PHONY: down
down: ## Uninstall the CCF release (Docker Desktop cluster stays)
	-helm uninstall $(RELEASE) --namespace $(NAMESPACE) $(HELM_CTX)

.PHONY: pf
pf: ## Port-forward UI (8000) and API (8080) on Docker Desktop
	@$(MAKE) --no-print-directory _pf KUBE_CONTEXT=$(KUBE_CONTEXT)

.PHONY: pf-aks
pf-aks: ## Port-forward UI (8000) and API (8080) on the current (AKS) context
	@$(MAKE) --no-print-directory _pf KUBE_CONTEXT=$(shell kubectl config current-context)

.PHONY: _pf
_pf:
	@echo "Context: $(KUBE_CONTEXT)"
	@echo "UI  -> http://localhost:8000"
	@echo "API -> http://localhost:8080"
	@trap 'kill 0' EXIT; \
	kubectl --context $(KUBE_CONTEXT) -n $(NAMESPACE) port-forward svc/$(RELEASE)-ui 8000:80 & \
	kubectl --context $(KUBE_CONTEXT) -n $(NAMESPACE) port-forward svc/$(RELEASE)-api 8080:8080 & \
	wait

.PHONY: status
status: ## Show CCF pods and services
	$(KUBECTL) get pods,svc -n $(NAMESPACE)

.PHONY: docker-ensure
docker-ensure: ## Verify Docker Desktop Kubernetes is enabled and reachable
	@kubectl config get-contexts $(KUBE_CONTEXT) >/dev/null 2>&1 || { \
		echo "ERROR: kube-context '$(KUBE_CONTEXT)' not found."; \
		echo "Enable it in Docker Desktop: Settings > Kubernetes > Enable Kubernetes."; \
		exit 1; }
	@$(KUBECTL) cluster-info >/dev/null 2>&1 || { \
		echo "ERROR: cannot reach '$(KUBE_CONTEXT)'. Is Docker Desktop running with Kubernetes enabled?"; \
		exit 1; }
	@echo "Docker Desktop Kubernetes is reachable (context: $(KUBE_CONTEXT))"

## ---------------------------------------------------------------- AKS demo
.PHONY: install-aks
install-aks: deps ## Install CCF on the CURRENT context (AKS) with the aks overlay
	@echo "Deploying to current context: $$(kubectl config current-context)"
	helm upgrade --install $(RELEASE) $(CHART_DIR) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(ENV_AKS) $(OVERLAY_ARGS) --wait --timeout 8m
	@echo "Expose it with:  make pf-aks   then open http://localhost:8000"

## ---------------------------------------------------------------- build & test
.PHONY: deps
deps: ## Build umbrella chart dependencies (vendored subchart .tgz)
	helm dependency build $(CHART_DIR)

.PHONY: lint
lint: ## helm lint umbrella + subcharts
	helm lint $(CHART_DIR)
	helm lint $(CHART_DIR)/charts/ccf-app
	helm lint $(CHART_DIR)/charts/ccf-agent

.PHONY: validate
validate: deps lint template-all ## Offline validation: lint + render every env/plugin combo
	@echo "OK: charts lint and every environment x plugin overlay renders."

.PHONY: template-all
template-all: deps ## Render every environment x plugin overlay combination (no cluster)
	@set -e; \
	for env in $(ENV_LOCAL) $(ENV_AKS); do \
		echo "--- $$env (base) ---"; \
		helm template $(RELEASE) $(CHART_DIR) -f $$env >/dev/null; \
		for plugin in values/plugins/*.yaml; do \
			echo "--- $$env + $$plugin ---"; \
			helm template $(RELEASE) $(CHART_DIR) -f $$env -f $$plugin \
				--set-string ccf-agent.config.plugins.github_repos.config.token=dummy \
				--set-string ccf-agent.config.plugins.github_repos.config.organization=dummy >/dev/null; \
		done; \
		echo "--- $$env + values/postgres-ha.yaml ---"; \
		helm template $(RELEASE) $(CHART_DIR) -f $$env -f values/postgres-ha.yaml \
			--set-string postgresql.auth.password=dummy \
			--set-string ccf-app.postgres.auth.password=dummy >/dev/null; \
	done; \
	echo "all combinations rendered successfully"

.PHONY: smoke
smoke: ## Post-deploy smoke test: wait for rollouts, then run helm tests
	$(KUBECTL) -n $(NAMESPACE) rollout status statefulset/$(RELEASE)-postgres --timeout=180s
	$(KUBECTL) -n $(NAMESPACE) rollout status deploy/$(RELEASE)-api --timeout=180s
	$(KUBECTL) -n $(NAMESPACE) rollout status deploy/$(RELEASE)-ui --timeout=180s
	$(KUBECTL) -n $(NAMESPACE) rollout status deploy/ccf-agent --timeout=180s
	@$(MAKE) --no-print-directory test

.PHONY: test
test: ## Run helm test hooks (in-cluster API/UI connectivity)
	helm test $(RELEASE) -n $(NAMESPACE) $(HELM_CTX) --logs

## ---------------------------------------------------------------- custom policies
.PHONY: policy-validate
policy-validate: ## opa check: compile/type-check custom Rego policies
	opa check $(POLICY_DIR)

.PHONY: policy-test
policy-test: ## opa test: run custom policy unit tests
	opa test $(POLICY_DIR) -v

.PHONY: policy-build
policy-build: policy-validate ## Build the custom policy OCI bundle
	@mkdir -p $(dir $(POLICY_BUNDLE))
	opa build -b $(POLICY_DIR) -o $(POLICY_BUNDLE)
	@echo "built $(POLICY_BUNDLE)"

.PHONY: policy-push
policy-push: policy-build ## Push the policy bundle to an OCI registry (POLICY_IMAGE, GHCR_USER, GHCR_TOKEN)
	@command -v gooci >/dev/null 2>&1 || { echo "installing gooci $(GOOCI_VERSION)..."; go install github.com/compliance-framework/gooci@$(GOOCI_VERSION); }
	@test -n "$(GHCR_TOKEN)" || { echo "GHCR_TOKEN is required (read/write packages token)"; exit 1; }
	gooci login ghcr.io --username $(GHCR_USER) --password $(GHCR_TOKEN)
	gooci upload-single $(POLICY_BUNDLE) $(POLICY_IMAGE)
	@echo "pushed $(POLICY_IMAGE)"

## ---------------------------------------------------------------- standalone charts
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
