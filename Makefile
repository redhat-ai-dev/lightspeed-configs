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
CONTAINER_ENGINE ?= podman
COMPOSE ?= $(CONTAINER_ENGINE) compose

ENV_FILES := --env-file env/default-values.env
ifneq ($(wildcard env/values.env),)
ENV_FILES += --env-file env/values.env
endif

LOCAL_COMPOSE_FILES := -f compose/compose.yaml

LIGHTSPEED_STACK_CONFIG := lightspeed-core-configs/lightspeed-stack.yaml
ifneq ($(wildcard lightspeed-core-configs/lightspeed-stack.local.yaml),)
LIGHTSPEED_STACK_CONFIG := lightspeed-core-configs/lightspeed-stack.local.yaml
endif
export LIGHTSPEED_STACK_CONFIG

.PHONY: default
default: help

.PHONY: get-rag
get-rag: ## Download a copy of the RAG embedding model and vector database
	@$(CONTAINER_ENGINE) rm tmp-rag-container 2>/dev/null || true
	$(CONTAINER_ENGINE) create --name tmp-rag-container $(RAG_CONTENT_IMAGE) true
	rm -rf rag-content
	mkdir -p rag-content
	$(CONTAINER_ENGINE) cp tmp-rag-container:/rag/vector_db rag-content
	$(CONTAINER_ENGINE) cp tmp-rag-container:/rag/embeddings_model rag-content
	$(CONTAINER_ENGINE) rm tmp-rag-container

.PHONY: get-skills
get-skills: ## Fetch RHDH skills from GitHub into the skills/ directory
	bash scripts/fetch-skills.sh

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

.PHONY: validate-prompt-templates
validate-prompt-templates: ## Validate prompt templates are in sync
	python3 scripts/sync-prompt-templates.py validate

.PHONY: update-prompt-templates
update-prompt-templates: ## Sync prompt templates from rhdh-profile.py
	python3 scripts/sync-prompt-templates.py update

.PHONY: sync-images
sync-images: ## Sync image values from images.yaml into default-values.env
	bash scripts/sync-images.sh

.PHONY: validate-images
validate-images: ## Validate that images.yaml and default-values.env are in sync
	bash scripts/validate-images.sh


.PHONY: validate-yaml
validate-yaml:
	yarn verify

.PHONY: format-yaml
format-yaml:
	yarn format
