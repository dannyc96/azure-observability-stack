# Azure observability stack: one command in, one command out.

TF_DIR      := terraform
APP_DIR     := app
IMAGE       ?= ghcr.io/dannyc96/orders-api:latest
TRAFFIC_SECONDS ?= 300

.PHONY: help deploy destroy fmt validate lint build-image push-image traffic

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

deploy: ## terraform init + apply the full stack
	terraform -chdir=$(TF_DIR) init
	terraform -chdir=$(TF_DIR) apply

destroy: ## Tear everything down (returns cost to $$0)
	terraform -chdir=$(TF_DIR) destroy

fmt: ## Format Terraform and Python
	terraform fmt -recursive $(TF_DIR)
	@command -v ruff >/dev/null && ruff format $(APP_DIR) || echo "ruff not installed, skipping python format"

validate: ## terraform validate without touching a backend
	terraform -chdir=$(TF_DIR) init -backend=false -input=false
	terraform -chdir=$(TF_DIR) validate

lint: ## tflint + ruff + compile-check the app
	@command -v tflint >/dev/null || { echo "tflint not installed (brew install tflint)"; exit 1; }
	tflint --init --config="$(CURDIR)/.tflint.hcl"
	tflint --chdir=$(TF_DIR) --config="$(CURDIR)/.tflint.hcl"
	@command -v ruff >/dev/null && ruff check $(APP_DIR) || echo "ruff not installed, skipping python lint"
	python3 -m py_compile $(APP_DIR)/main.py

build-image: ## Build the orders API container image
	docker build -t $(IMAGE) $(APP_DIR)

push-image: build-image ## Build and push the image (docker login first)
	docker push $(IMAGE)

traffic: ## Generate demo traffic against the deployed app
	./scripts/generate-traffic.sh "https://$$(terraform -chdir=$(TF_DIR) output -raw app_fqdn)" $(TRAFFIC_SECONDS)
