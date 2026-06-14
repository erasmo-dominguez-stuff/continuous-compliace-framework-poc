# CCF Helm chart - local (Docker Desktop) & AKS helpers.
# Full documentation: docs/README.md
#
# Headline commands:
#   make up      # start the full CCF stack locally (Docker Desktop)
#   make obs     # start the observability stack (Loki/Prometheus/Grafana/Alloy)
#   make pf-all  # port-forward everything (CCF UI/API + Grafana/Prometheus/Loki)
#   make aks     # install CCF on AKS (current kube-context)
#   make prod    # production profile on current kube-context (see docs/production.md)
#   make policy  # validate + unit-test the custom Rego policies
#   make down    # uninstall the CCF release
#
# Local demo (Docker Desktop Kubernetes):
#   make up && make pf          # then open http://localhost:8000
#   #                             (admin@ccf.local / Admin12345!)
#
# AKS demo:
#   az aks get-credentials --resource-group <rg> --name <aks>   # selects the context
#   make aks ADMIN_PASSWORD='<strong-pw>'
#   make pf-aks                 # port-forward against the current (AKS) context
#
# Optional add-ons (any environment):
#   GITHUB plugin:  make up PLUGIN_VALUES="values/plugins/local-ssh.yaml values/plugins/github.yaml" \
#                     GITHUB_TOKEN=... GITHUB_ORG=...
#   HA Postgres:    make up EXTRA_VALUES="values/postgres-ha.yaml" PG_PASSWORD=...

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
ENV_PROD  ?= values/production.yaml

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

# SEED=1 imports a small demo OSCAL dataset (catalog + SSP + plan + results +
# POA&M) so the UI isn't empty on a fresh install. Off unless requested.
SEED_ARGS :=
ifneq ($(strip $(SEED)),)
SEED_ARGS += --set ccf-app.api.seedData.enabled=true
endif

# Everything layered after the environment overlay.
OVERLAY_ARGS := $(PLUGIN_ARGS) $(EXTRA_ARGS) $(SECRET_ARGS) $(SEED_ARGS)

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
up: deps docker-ensure ## Start the full CCF stack locally on Docker Desktop (then `make pf`)
	helm upgrade --install $(RELEASE) $(CHART_DIR) $(HELM_CTX) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(ENV_LOCAL) $(OVERLAY_ARGS) --wait --timeout 5m
	@$(MAKE) --no-print-directory status
	@echo ""
	@echo "CCF is up on '$(KUBE_CONTEXT)'. Expose it with:  make pf"
	@echo "Then open http://localhost:8000  (admin@ccf.local / Admin12345!)"

.PHONY: obs
obs: obs-stack obs-alloy ## Start the observability stack (Loki/Prometheus/Grafana/Alloy)
	@echo ""
	@echo "Observability installed in namespace '$(OBS_NAMESPACE)'."
	@echo "See everything with:  make pf-all   (Grafana on http://localhost:3000, admin/admin)"

.PHONY: down
down: ## Uninstall the CCF release (Docker Desktop cluster stays)
	-helm uninstall $(RELEASE) --namespace $(NAMESPACE) $(HELM_CTX)

.PHONY: pf
pf: ## Port-forward UI (8000) and API (8080) on Docker Desktop
	@$(MAKE) --no-print-directory _pf KUBE_CONTEXT=$(KUBE_CONTEXT)

.PHONY: pf-aks
pf-aks: ## (AKS) Port-forward UI (8000) and API (8080) on the current context
	@$(MAKE) --no-print-directory _pf KUBE_CONTEXT=$(shell kubectl config current-context)

.PHONY: pf-all
pf-all: ## Port-forward everything useful: UI, API, Grafana, Prometheus, Loki
	@echo "Context: $(KUBE_CONTEXT)"
	@echo "UI         -> http://localhost:8000"
	@echo "API        -> http://localhost:8080"
	@echo "Grafana    -> http://localhost:3000   (admin / admin)"
	@echo "Prometheus -> http://localhost:9091"
	@echo "Loki       -> http://localhost:3100"
	@echo "(observability targets are skipped silently if not installed)"
	@trap 'kill 0' EXIT; \
	$(KUBECTL) -n $(NAMESPACE) port-forward svc/$(RELEASE)-ui 8000:80 & \
	$(KUBECTL) -n $(NAMESPACE) port-forward svc/$(RELEASE)-api 8080:8080 & \
	$(KUBECTL) -n $(OBS_NAMESPACE) port-forward svc/ccf-grafana 3000:80 2>/dev/null & \
	$(KUBECTL) -n $(OBS_NAMESPACE) port-forward svc/prometheus-server 9091:80 2>/dev/null & \
	$(KUBECTL) -n $(OBS_NAMESPACE) port-forward svc/loki 3100:3100 2>/dev/null & \
	wait

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
docker-ensure: # Verify Docker Desktop Kubernetes is enabled and reachable
	@kubectl config get-contexts $(KUBE_CONTEXT) >/dev/null 2>&1 || { \
		echo "ERROR: kube-context '$(KUBE_CONTEXT)' not found."; \
		echo "Enable it in Docker Desktop: Settings > Kubernetes > Enable Kubernetes."; \
		exit 1; }
	@$(KUBECTL) cluster-info >/dev/null 2>&1 || { \
		echo "ERROR: cannot reach '$(KUBE_CONTEXT)'. Is Docker Desktop running with Kubernetes enabled?"; \
		exit 1; }
	@echo "Docker Desktop Kubernetes is reachable (context: $(KUBE_CONTEXT))"

## ---------------------------------------------------------------- AKS
.PHONY: aks
aks: deps ## (AKS) Install CCF on the CURRENT kube-context with the aks overlay
	@echo "Deploying to current context: $$(kubectl config current-context)"
	helm upgrade --install $(RELEASE) $(CHART_DIR) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(ENV_AKS) $(OVERLAY_ARGS) --wait --timeout 8m
	@echo "Expose it with:  make pf-aks   then open http://localhost:8000"

.PHONY: install-aks
install-aks: aks # Backwards-compatible alias for `make aks`

.PHONY: prod
prod: deps ## Production CCF on current kube-context (values/production.yaml + optional overlays)
	@test -n "$(ADMIN_PASSWORD)" || { echo "ADMIN_PASSWORD is required. Create K8s Secrets first — see docs/production.md"; exit 1; }
	@test -n "$(strip $(PLUGIN_VALUES))" && test "$(PLUGIN_VALUES)" != "values/plugins/local-ssh.yaml" || \
		{ echo "WARNING: production agent needs at least one plugin overlay (PLUGIN_VALUES=values/plugins/github.yaml)"; }
	@echo "Deploying production profile to: $$(kubectl config current-context)"
	helm upgrade --install $(RELEASE) $(CHART_DIR) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(ENV_PROD) $(OVERLAY_ARGS) --wait --timeout 10m
	@echo "Production CCF installed. Next: make obs && make pf-aks  (or configure ingress in values/production.yaml)"

## ---------------------------------------------------------------- build & test
.PHONY: deps
deps: # Build umbrella chart dependencies (vendored subchart .tgz)
	helm dependency build $(CHART_DIR)

.PHONY: lint
lint: # helm lint umbrella + subcharts
	helm lint $(CHART_DIR)
	helm lint $(CHART_DIR)/charts/ccf-app
	helm lint $(CHART_DIR)/charts/ccf-agent

.PHONY: validate
validate: deps lint template-all ## Offline validation: lint + render every env/plugin combo
	@echo "OK: charts lint and every environment x plugin overlay renders."

.PHONY: template-all
template-all: deps # Render every environment x plugin overlay combination (no cluster)
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
	for prod in values/production.yaml values/production-ha.yaml; do \
		echo "--- $$prod (base) ---"; \
		helm template $(RELEASE) $(CHART_DIR) -f $$prod \
			--set-string ccf-app.api.adminUser.password=dummy \
			--set-string postgresql.auth.password=dummy >/dev/null; \
		echo "--- values/aks.yaml + $$prod ---"; \
		helm template $(RELEASE) $(CHART_DIR) -f values/aks.yaml -f $$prod \
			--set-string ccf-app.api.adminUser.password=dummy \
			--set-string postgresql.auth.password=dummy >/dev/null; \
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
test: # Run helm test hooks (in-cluster API/UI connectivity)
	helm test $(RELEASE) -n $(NAMESPACE) $(HELM_CTX) --logs

## ---------------------------------------------------------------- custom policies
.PHONY: policy
policy: policy-validate policy-test ## Validate + unit-test the custom Rego policies
	@echo "OK: custom policies compile and pass their unit tests."

.PHONY: policy-validate
policy-validate: # opa check: compile/type-check custom Rego policies
	opa check $(POLICY_DIR)

.PHONY: policy-test
policy-test: # opa test: run custom policy unit tests
	opa test $(POLICY_DIR) -v

.PHONY: policy-build
policy-build: policy-validate # Build the custom policy OCI bundle
	@mkdir -p $(dir $(POLICY_BUNDLE))
	opa build -b $(POLICY_DIR) -o $(POLICY_BUNDLE)
	@echo "built $(POLICY_BUNDLE)"

.PHONY: policy-push
policy-push: policy-build ## Build & push the policy bundle to an OCI registry (POLICY_IMAGE, GHCR_USER, GHCR_TOKEN)
	@command -v gooci >/dev/null 2>&1 || { echo "installing gooci $(GOOCI_VERSION)..."; go install github.com/compliance-framework/gooci@$(GOOCI_VERSION); }
	@test -n "$(GHCR_TOKEN)" || { echo "GHCR_TOKEN is required (read/write packages token)"; exit 1; }
	gooci login ghcr.io --username $(GHCR_USER) --password $(GHCR_TOKEN)
	gooci upload-single $(POLICY_BUNDLE) $(POLICY_IMAGE)
	@echo "pushed $(POLICY_IMAGE)"

## ---------------------------------------------------------------- standalone charts
.PHONY: install-app
install-app: deps # Install ccf-app standalone (production values)
	helm upgrade --install ccf-app $(CHART_DIR)/charts/ccf-app $(HELM_CTX) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(CHART_DIR)/charts/ccf-app/values-production.yaml

.PHONY: install-agent
install-agent: # Install ccf-agent standalone (production values)
	helm upgrade --install ccf-agent $(CHART_DIR)/charts/ccf-agent $(HELM_CTX) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(CHART_DIR)/charts/ccf-agent/values-production.yaml

## ---------------------------------------------------------------- observability (internals)
.PHONY: obs-repos
obs-repos: # Add Grafana/Prometheus helm repos
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update

.PHONY: obs-stack
obs-stack: obs-repos # Install Loki + Prometheus + Grafana (pre-provisioned) for local testing
	helm upgrade --install loki grafana/loki $(HELM_CTX) \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		--set deploymentMode=SingleBinary \
		--set loki.commonConfig.replication_factor=1 \
		--set loki.storage.type=filesystem \
		--set loki.useTestSchema=true \
		--set loki.auth_enabled=false \
		--set singleBinary.replicas=1 \
		--set read.replicas=0 --set write.replicas=0 --set backend.replicas=0 \
		--set chunksCache.enabled=false --set resultsCache.enabled=false
	helm upgrade --install prometheus prometheus-community/prometheus $(HELM_CTX) \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		--set server.extraFlags="{web.enable-remote-write-receiver}" \
		--set alertmanager.enabled=false \
		--set prometheus-pushgateway.enabled=false \
		-f observability/prometheus-values.yaml
	helm upgrade --install ccf-grafana grafana/grafana $(HELM_CTX) \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		-f observability/grafana-values.yaml

.PHONY: obs-alloy
obs-alloy: obs-repos # Install Grafana Alloy to collect CCF logs & metrics
	helm upgrade --install ccf-alloy grafana/alloy $(HELM_CTX) \
		--namespace $(OBS_NAMESPACE) --create-namespace \
		-f observability/alloy-values.yaml

.PHONY: obs-grafana
obs-grafana: # Port-forward Grafana (3000) - CCF dashboard, admin/admin
	@echo "Grafana -> http://localhost:3000   (admin / admin)"
	@echo "Dashboard: CCF - Logs & Metrics"
	$(KUBECTL) -n $(OBS_NAMESPACE) port-forward svc/ccf-grafana 3000:80

.PHONY: obs-loki
obs-loki: # Port-forward Loki (3100) for raw querying
	$(KUBECTL) -n $(OBS_NAMESPACE) port-forward svc/loki 3100:3100
