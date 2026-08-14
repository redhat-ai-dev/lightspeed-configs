# Contributing

- [Prerequisites](#prerequisites)
- [Running Locally](#running-locally)
- [Configuring RAG Content](#configuring-rag-content)
- [Configuring Skills](#configuring-skills)
- [Configuring Validation](#configuring-validation)
- [Syncing Configs](#syncing-configs)
  - [Syncing Images](#syncing-images)
- [Formatting and Validating YAML](#formatting-and-validating-yaml)
- [Makefile Commands](#makefile-commands)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- [Podman](https://podman.io/docs/installation) v5.4.1+ (recommended) or [Docker](https://docs.docker.com/engine/) v28.1.0+ with Compose support
- [yq](https://github.com/mikefarah/yq) v4.52.4+ for image and config sync/validation
- `python3.12+` for the prompt-template sync/validation scripts

## Running Locally

1. Copy `./env/default-values.env` to `./env/values.env` and fill in any provider-specific values (see [docs/PROVIDERS.md](./PROVIDERS.md)).

   To configure inference providers without editing the git-tracked `lightspeed-stack.yaml`, copy `lightspeed-core-configs/lightspeed-stack.yaml` to `lightspeed-core-configs/lightspeed-stack.local.yaml` and make your edits there. `make local-up` mounts the `.local.yaml` file automatically when it's present, otherwise it falls back to `lightspeed-stack.yaml`. `lightspeed-stack.local.yaml` is gitignored, so it's safe to leave provider config there permanently.

   The tracked `lightspeed-stack.yaml` contains commented stubs for `vllm`, `openai`, and `vertexai`. Copy it to `lightspeed-stack.local.yaml` and uncomment the provider block(s) you need. For GitOps/production, [scripts/generate-gitops-manifests.sh](../scripts/generate-gitops-manifests.sh) uncomments those three providers and adds production `allowed_models`. Ollama (if needed) is added manually in `.local.yaml` — see [docs/PROVIDERS.md](./PROVIDERS.md).

2. Pull the RAG content:

```sh
make get-rag
```

3. Optional: pull RHDH skills for skills consumption:

```sh
make get-skills
```

4. The production config (`lightspeed-stack.yaml`) sets `host: 127.0.0.1` so the service only binds to loopback — reachable exclusively by containers in the same Pod on Kubernetes. The compose file overrides this with `SERVICE_HOST=0.0.0.0` so the container port mapping works and you can reach the API at `localhost:8080` from your host.

1. Start the local API stack:

```sh
make local-up
```

This starts Lightspeed Core using the mounted config/content below.

Lightspeed Core uses mounted config/content in local compose:

- `lightspeed-core-configs/lightspeed-stack.yaml` (or `lightspeed-stack.local.yaml`, if present) -> `/app-root/lightspeed-stack.yaml`
- `lightspeed-core-configs/rhdh-profile.py` -> `/app-root/rhdh-profile.py`
- `llama-stack-configs/config.yaml` -> `/app-root/config.yaml`
- `rag-content/` -> `/rag-content`

Question validation is not enabled automatically. If you want it, set `ENABLE_VALIDATION=question_validity`, `VALIDATION_PROVIDER`, and `VALIDATION_MODEL_NAME` in `env/values.env`, along with any env vars required by the selected inference provider.

See [Configuring Validation](#configuring-validation) for example configurations.

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

> [!IMPORTANT]
> The vector store ID changes whenever the RAG content image is updated. Update `byok_rag` once per image.

Product docs RAG is configured in [`lightspeed-core-configs/lightspeed-stack.yaml`](../lightspeed-core-configs/lightspeed-stack.yaml) under `byok_rag` (not in the Llama Stack profile). After `make get-rag`, open `rag-content/vector_db/rhdh_product_docs/<docs number>/llama-stack.yaml` and copy `vector_store_id` from the `vector_stores` section, for example:

```yaml
vector_stores:
  - embedding_dimension: 768
    embedding_model: sentence-transformers//rag-content/embeddings_model
    provider_id: rhdh-product-docs-1_8
    vector_store_id: vs_3d47e06c-ac95-49b6-9833-d5e6dd7252dd
```

Paste that value into `byok_rag[].vector_db_id`. Keep `embedding_model` as the double-slash form `sentence-transformers//rag-content/embeddings_model` so Llama Stack’s registry id matches the load path. Point `db_path` at the FAISS db under `./rag-content` (mounted at `/rag-content` in the container).

> [!NOTE]
> Until OKP replaces the historic RAG setup, prebuilt FAISS DBs from `make get-rag` can return **0 chunks** with OGX. The index is stored under a bare Llama Stack key (`faiss_index:v3::vs_…`), while OGX reads the same SQLite file with persistence namespace `vector_io::faiss` and looks for `vector_io::faiss:faiss_index:v3::vs_…`.
>
> After `make get-rag`, copy the index under the namespaced key (adjust the docs version and `vs_…` id from `llama-stack.yaml`), then restart local services:
>
> ```sh
> sqlite3 rag-content/vector_db/rhdh_product_docs/1.10/faiss_store.db <<'SQL'
> INSERT OR REPLACE INTO kvstore (key, value, expiration)
> SELECT 'vector_io::faiss:' || key, value, expiration
> FROM kvstore
> WHERE key = 'faiss_index:v3::vs_757285d9-b657-4bed-b18c-3359844e8c0d';
> SQL
> ```
>
> Re-run this after every `make get-rag` until OKP is added.

`notebooks` is separate: it is dynamic create capacity under `vector_store` (local FAISS; GitOps rewrites it to pgvector). It is not a second `byok_rag` corpus.

If you use a gitignored `lightspeed-stack.local.yaml` for local providers, copy the same `byok_rag` / `rag` / `vector_store` / `shields` sections from the committed file when they change.

## Configuring Skills

`make get-skills` is optional and only needed for skills consumption. It pulls skills from the [rhdh-skills](https://github.com/redhat-developer/rhdh-skills) repository into `./skills`, which `make local-up` mounts read-only to `/app-root/skills` (configured under `skills.paths` in [`lightspeed-stack.yaml`](../lightspeed-core-configs/lightspeed-stack.yaml)). It fully replaces the directory contents on each run.

To use a different skills repo/ref:

```sh
make get-skills RHDH_SKILLS_REPO=<git-url> RHDH_SKILLS_REF=<branch-or-tag>
```

Restart local services after fetching skills for them to take effect:

```sh
make local-down && make local-up
```

## Configuring Validation

Question validation is owned by Lightspeed Core (not Llama Stack / OGX Safety). It is configured under `shields` in [`lightspeed-stack.yaml`](../lightspeed-core-configs/lightspeed-stack.yaml) as a `question_validity` shield, including the RHDH classifier `model_prompt` and `invalid_question_response`.

Opt-in uses OGX's `__disabled__` provider skip: when `ENABLE_VALIDATION` is unset, `provider_id` defaults to `__disabled__` and the shield entry is omitted (so `VALIDATION_*` need not be set). When enabling, set `ENABLE_VALIDATION` to the shield provider id `question_validity` — not `true` (that value is no longer valid after the LCORE migration).

`make local-up` does not start a validation service or inject validation defaults. If you enable validation, you must provide both `VALIDATION_PROVIDER` and `VALIDATION_MODEL_NAME` yourself in `env/values.env`.

| Variable | Required | Description |
| ---- | ---- | ---- |
| `ENABLE_VALIDATION` | Yes, set to `question_validity` | Activates the LCORE `shields` entry (unset → disabled) |
| `VALIDATION_PROVIDER` | Yes, when enabling | Inference provider id used in `model_id` (`provider/model`), for example `vllm` or `openai` |
| `VALIDATION_MODEL_NAME` | Yes, when enabling | Model name served by the selected inference provider |

The referenced inference provider must also be present in `lightspeed-stack.yaml` (or `lightspeed-stack.local.yaml`) and configured via its env vars. See [docs/PROVIDERS.md](./PROVIDERS.md). Examples:

### Example: vLLM-backed validation

```env
ENABLE_VALIDATION=question_validity
VALIDATION_PROVIDER=vllm
VALIDATION_MODEL_NAME=<your-model-name>
VLLM_URL=<your-vllm-endpoint>
VLLM_API_KEY=<api-key>
```

> [!IMPORTANT]
> Deployments that previously set `ENABLE_VALIDATION=true` (for the old Llama Stack safety provider) must switch to `ENABLE_VALIDATION=question_validity`, or LCORE will reject the shield `provider_id`.


## Syncing Configs

This repository has sync scripts that keep generated values consistent with their sources. CI validates these on every PR -- if they drift, the PR will fail.

### Syncing Images

[images.yaml](./images.yaml) is the source of truth for sprint images. It is also consumed by an external service for a different environment. The image values in `env/default-values.env` must stay in sync with it.

After updating `images.yaml`:

```sh
make sync-images
```

This reads the `image` field for each service in `images.yaml` and updates the corresponding env vars (`LIGHTSPEED_CORE_IMAGE`, `RAG_CONTENT_IMAGE`) in `env/default-values.env`.

`lightspeed-core-configs/rhdh-profile.py` is maintained directly in this repository (not synced from upstream). Keep `customization.profile_path` in `lightspeed-core-configs/lightspeed-stack.yaml` aligned with the mount path configured in `compose/compose.yaml` (`/app-root/rhdh-profile.py`).

### Syncing Prompt Templates

The question-validation `model_prompt` and `invalid_question_response` in `lightspeed-core-configs/lightspeed-stack.yaml` (under `shields`) are sourced from `lightspeed-core-configs/rhdh-profile.py`.

`make update-prompt-templates` and `make validate-prompt-templates` call `scripts/sync-prompt-templates.py` directly with `python3`. The helper requires Python 3.12+ and will exit with a clear error if invoked with an older interpreter.

The Python helper is used because the source of truth lives in a Python file and the sync step needs to parse Python triple-quoted strings, translate placeholders for the Llama Stack YAML (`{SUBJECT_ALLOWED}` -> `${allowed}`, `{SUBJECT_REJECTED}` -> `${rejected}`, `{{query}}` -> `${message}`), and rewrite YAML block scalars in a stable format. The helper uses only the Python standard library.

After updating `QUESTION_VALIDATOR_PROMPT_TEMPLATE` or `INVALID_QUERY_RESP` in `lightspeed-core-configs/rhdh-profile.py`:

```sh
make update-prompt-templates
make validate-prompt-templates
```

## Formatting and Validating YAML

Format and validate YAML files (also used by CI):

```sh
make format-yaml
make validate-yaml
```

## Makefile Commands

| Command | Description |
| ---- | ---- |
| `get-rag` | Pull and unpack RAG content into `./rag-content` (replaces existing contents). Optional: `RAG_CONTENT_IMAGE=<image>`. |
| `get-skills` | Optional. Fetch RHDH skills into `./skills` for skills consumption (replaces existing contents). Optional: `RHDH_SKILLS_REPO=<url>`, `RHDH_SKILLS_REF=<ref>`. |
| `local-up` | Start local compose services. Validation is controlled entirely through env vars in `env/values.env`. |
| `local-down` | Stop local compose services. |
| `sync-images` | Sync image values from `images.yaml` into `env/default-values.env`. Requires `yq`. |
| `validate-images` | Validate that `images.yaml` and `env/default-values.env` are in sync. Requires `yq`. |
| `validate-yaml` | Validate YAML formatting/syntax. |
| `format-yaml` | Format YAML files. |
| `validate-prompt-templates` | Validate that the question-validation prompt values in `lightspeed-core-configs/lightspeed-stack.yaml` match `lightspeed-core-configs/rhdh-profile.py`. |
| `update-prompt-templates` | Sync the question-validation prompt values in `lightspeed-core-configs/lightspeed-stack.yaml` from `lightspeed-core-configs/rhdh-profile.py`. |

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
