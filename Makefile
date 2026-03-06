#
#
# Copyright Red Hat
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
RAG_CONTENT_IMAGE ?= $(shell grep '^RAG_CONTENT_IMAGE=' env/default-values.env | cut -d= -f2-)
QUESTION_VALIDATION_TAG ?= 0.1.17
QUESTION_VALIDATION_URL ?= https://raw.githubusercontent.com/lightspeed-core/lightspeed-providers/refs/tags/$(QUESTION_VALIDATION_TAG)/resources/external_providers/inline/safety/lightspeed_question_validity.yaml
COMPOSE ?= podman compose
WITH_SAFETY ?= true

ENV_FILES := --env-file env/default-values.env
ifneq ($(wildcard env/values.env),)
ENV_FILES += --env-file env/values.env
endif

ifeq ($(WITH_SAFETY),false)
LOCAL_COMPOSE_FILES := -f compose/compose.yaml
else
LOCAL_COMPOSE_FILES := -f compose/compose.yaml -f compose/compose.ollama.yaml
endif

VENV := $(CURDIR)/scripts/python-scripts/.venv
PYTHON := $(VENV)/bin/python3
PIP := $(VENV)/bin/pip3

.PHONY: default
default: help

.PHONY: get-rag
get-rag: ## Download a copy of the RAG embedding model and vector database
	podman create --replace --name tmp-rag-container $(RAG_CONTENT_IMAGE) true
	rm -rf rag-content
	mkdir -p rag-content
	podman cp tmp-rag-container:/rag/vector_db rag-content
	podman cp tmp-rag-container:/rag/embeddings_model rag-content
	podman rm tmp-rag-container

.PHONY: local-up
local-up:
	$(COMPOSE) $(ENV_FILES) $(LOCAL_COMPOSE_FILES) up -d

.PHONY: local-down
local-down:
	$(COMPOSE) $(ENV_FILES) $(LOCAL_COMPOSE_FILES) down

.PHONY: help
help: ## Show this help screen
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@echo ''
	@grep -E '^[ a-zA-Z0-9_.-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-33s\033[0m %s\n", $$1, $$2}'
	@echo ''

.PHONY: update-question-validation
update-question-validation:
	curl -o ./config/providers.d/inline/safety/lightspeed_question_validity.yaml $(QUESTION_VALIDATION_URL)

$(VENV)/bin/activate: ./scripts/python-scripts/requirements.txt
	python3 -m venv $(VENV)
	$(PIP) install -r scripts/python-scripts/requirements.txt
	touch $(VENV)/bin/activate

define run_sync
	cd ./scripts/python-scripts && \
	$(PYTHON) sync.py -t $(1)
endef

.PHONY: validate-prompt-templates
validate-prompt-templates: $(VENV)/bin/activate
	$(call run_sync,validate)

.PHONY: update-prompt-templates
update-prompt-templates: $(VENV)/bin/activate
	$(call run_sync,update)

.PHONY: sync-images
sync-images: ## Sync image values from images.yaml into default-values.env
	bash scripts/sync-images.sh

.PHONY: validate-images
validate-images: ## Validate that images.yaml and default-values.env are in sync
	bash scripts/validate-images.sh

.PHONY: sync-compose-config
sync-compose-config: ## Sync compose lightspeed-stack config from lightspeed-core-configs
	bash scripts/sync-compose-config.sh

.PHONY: validate-compose-config
validate-compose-config: ## Validate compose lightspeed-stack config is in sync with source
	bash scripts/validate-compose-config.sh

.PHONY: validate-yaml
validate-yaml:
	yarn verify

.PHONY: format-yaml
format-yaml:
	yarn format
