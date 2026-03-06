# Contributing

- [Prerequisites](#prerequisites)
- [Running Locally](#running-locally)
- [Configuring RAG Content](#configuring-rag-content)
- [Configuring Safety Guards](#configuring-safety-guards)
- [Syncing Configs](#syncing-configs)
  - [Syncing Images](#syncing-images)
  - [Syncing Compose Config](#syncing-compose-config)
- [Formatting and Validating YAML](#formatting-and-validating-yaml)
- [Makefile Commands](#makefile-commands)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- [Podman](https://podman.io/docs/installation) v5.4.1+ (recommended) or [Docker](https://docs.docker.com/engine/) v28.1.0+ with Compose support
- [yq](https://github.com/mikefarah/yq) v4.52.4+ for image and config sync/validation

## Running Locally

1. Copy `./env/default-values.env` to `./env/values.env` and fill in any provider-specific values (see [docs/PROVIDERS.md](./PROVIDERS.md)).

2. Pull the RAG content:

```sh
make get-rag
```

3. Start the local API stack:

```sh
make local-up
```

This starts Llama Stack, Lightspeed Core, and Ollama (for Llama Guard). Compose enforces startup order: Ollama healthy -> Llama Stack healthy -> Lightspeed Core starts.

To disable safety guards:

```sh
make local-up WITH_SAFETY=false
```

4. Stop services:

```sh
make local-down
```

## Configuring RAG Content

`make get-rag` pulls the embeddings model and vector database from the RAG content image into `./rag-content`. It fully replaces the directory on each run.

To use a different RAG image:

```sh
make get-rag RAG_CONTENT_IMAGE=quay.io/redhat-ai-dev/rag-content:<tag>
```

## Configuring Safety Guards

By default (`WITH_SAFETY=true`), `make local-up` uses `llama-stack-configs/run.yaml` which has Llama Guard enabled. The compose overlay starts an Ollama container and pulls the safety model automatically.

To skip safety guards for development, use `WITH_SAFETY=false` which uses `llama-stack-configs/run-no-guard.yaml` instead.

Relevant environment variables in `env/values.env`:

- `SAFETY_MODEL`: Llama Guard model name. Defaults to `llama-guard3:8b`
- `SAFETY_URL`: Endpoint URL. Defaults to `http://host.docker.internal:11434/v1`
- `SAFETY_API_KEY`: API key, not required for local

## Syncing Configs

This repository has sync scripts that keep derived files consistent with their sources. CI validates these on every PR -- if they drift, the PR will fail.

### Syncing Images

[images.yaml](./images.yaml) is the source of truth for sprint images. It is also consumed by an external service for a different environment. The image values in `env/default-values.env` must stay in sync with it.

After updating `images.yaml`:

```sh
make sync-images
```

This reads the `image` field for each service in `images.yaml` and updates the corresponding env vars (`LIGHTSPEED_CORE_IMAGE`, `LLAMA_STACK_IMAGE`, `RAG_CONTENT_IMAGE`) in `env/default-values.env`.

### Syncing Compose Config

`compose/lightspeed-stack.compose.yaml` is derived from `lightspeed-core-configs/lightspeed-stack.yaml`. The only difference is the `llama_stack.url` -- the compose version uses the Docker Compose service name (`http://llama-stack:8321`) instead of localhost.

After updating `lightspeed-core-configs/lightspeed-stack.yaml`:

```sh
make sync-compose-config
```

## Formatting and Validating YAML

Format and validate YAML files (also used by CI):

```sh
make format-yaml
make validate-yaml
```

Update the question-validation provider config from upstream:

```sh
make update-question-validation QUESTION_VALIDATION_TAG=0.1.17
```

## Makefile Commands

| Command | Description |
| ---- | ---- |
| `get-rag` | Pull and unpack RAG content into `./rag-content` (replaces existing contents). Optional: `RAG_CONTENT_IMAGE=<image>`. |
| `local-up` | Start local compose services. Default: `WITH_SAFETY=true` (uses `run.yaml`). Set `WITH_SAFETY=false` to use `run-no-guard.yaml`. |
| `local-down` | Stop local compose services. |
| `sync-images` | Sync image values from `images.yaml` into `env/default-values.env`. Requires `yq`. |
| `validate-images` | Validate that `images.yaml` and `env/default-values.env` are in sync. Requires `yq`. |
| `sync-compose-config` | Sync `compose/lightspeed-stack.compose.yaml` from `lightspeed-core-configs/lightspeed-stack.yaml`. Requires `yq`. |
| `validate-compose-config` | Validate that the compose config is in sync with its source. Requires `yq`. |
| `validate-yaml` | Validate YAML formatting/syntax. |
| `format-yaml` | Format YAML files. |
| `update-question-validation` | Update question-validation content in `config/providers.d`. Optional: `QUESTION_VALIDATION_TAG=<tag>`. |
| `validate-prompt-templates` | Validate prompt values against upstream templates. |
| `update-prompt-templates` | Update prompt values from upstream templates. |

## Troubleshooting

Enable debug logs:

```sh
LLAMA_STACK_LOGGING=all=DEBUG
```

If you hit a permission error for `vector_db`, such as:

```sh
sqlite3.OperationalError: attempt to write a readonly database
```

fix permissions with:

```sh
chmod -R 777 rag-content/vector_db
```

If `podman compose` delegates to `docker-compose` and you get a registry auth error like:

```sh
unable to retrieve auth token: invalid username/password: unauthorized
```

it means `docker-compose` cannot find your credentials. Even if you are logged in via `podman login`, `docker-compose` looks for credentials at `~/.docker/config.json`. Write your credentials there with:

```sh
mkdir -p ~/.docker
podman login --authfile ~/.docker/config.json registry.redhat.io
```
