#!/usr/bin/env bash
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
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/generated"
GITOPS_REPO="${GITOPS_REPO:-${REPO_ROOT}/../ai-rolling-demo-gitops}"

mkdir -p "${OUTPUT_DIR}"

indent() {
  sed 's/^/    /'
}

strip_license() {
  sed -n '/^[^#]/,$p' "$1"
}

strip_comments() {
  sed -E '/^[[:space:]]*#/d'
}

get_image() {
  local key="$1"
  awk -v key="${key}" '
    /^[^[:space:]]/ { in_section = ($0 == key":") }
    in_section && /^[[:space:]]+image:/ { print $2; exit }
  ' "${REPO_ROOT}/images.yaml"
}

# Rewrite high-level vector_store.providers notebooks FAISS → pgvector for cluster.
# Llama Stack HNSW/COSINE defaults match the former low-level rewrite (D6A).
notebooks_vector_store_faiss_to_pgvector() {
  awk '
    /^    - id: notebooks$/ {
      skip = 1
      print "    - id: notebooks"
      print "      type: pgvector"
      print "      embedding_model: nomic-ai/nomic-embed-text-v1.5"
      print "      embedding_dimension: 768"
      print "      config:"
      print "        host: ${env.PGVECTOR_HOST:=lightspeed-postgres-svc.lightspeed-postgres.svc.cluster.local}"
      print "        port: \"5432\"  # TODO: fix lcore parsing and revert back to env"
      print "        db: ${env.PGVECTOR_DB}"
      print "        user: ${env.PGVECTOR_USER}"
      print "        password: ${env.PGVECTOR_PASSWORD}"
      next
    }
    skip && /^    - id:/ { skip = 0 }
    skip && /^[a-zA-Z]/ { skip = 0 }
    skip { next }
    { print }
  '
}

# Uncomment commented inference provider blocks whose id is vllm, openai, or vertexai.
uncomment_inference_providers() {
  awk '
    function uncomment_line(text) {
      comment_pos = index(text, "#")
      if (comment_pos == 0) {
        return text
      }

      prefix = substr(text, 1, comment_pos - 1)
      rest = substr(text, comment_pos + 1)
      sub(/^[[:space:]]/, "", rest)
      return prefix rest
    }

    function flush_block(    i, line_out) {
      if (!buffering) {
        return
      }

      for (i = 1; i <= block_len; i++) {
        line_out = block_lines[i]
        if (block_id in enable) {
          line_out = uncomment_line(line_out)
        }
        print line_out
      }

      delete block_lines
      block_len = 0
      block_id = ""
      buffering = 0
    }

    BEGIN {
      enable["vllm"] = 1
      enable["openai"] = 1
      enable["vertexai"] = 1
    }

    {
      line = $0

      if (in_inference && line ~ /^[^[:space:]]/ && line != "inference:") {
        flush_block()
        in_inference = 0
        in_providers = 0
      }

      if (line == "inference:") {
        flush_block()
        in_inference = 1
        print line
        next
      }

      if (in_inference && line == "  providers:") {
        flush_block()
        in_providers = 1
        print line
        next
      }

      if (in_providers && line ~ /^  [^[:space:]#-]/) {
        flush_block()
        in_providers = 0
      }

      if (in_providers && line ~ /^[[:space:]]*#[[:space:]]*- type:/) {
        flush_block()
        buffering = 1
        block_lines[++block_len] = line
        next
      }

      if (buffering) {
        if (line ~ /^[[:space:]]*#/) {
          block_lines[++block_len] = line
          if (line ~ /^[[:space:]]*#[[:space:]]*id:[[:space:]]*/) {
            block_id = line
            sub(/^[[:space:]]*#[[:space:]]*id:[[:space:]]*/, "", block_id)
            sub(/[[:space:]].*$/, "", block_id)
          }
          next
        }

        flush_block()
      }

      print line
    }

    END {
      flush_block()
    }
  '
}

add_inference_allowed_models() {
  awk '
    /^    - type:/ {
      current_provider = ""
    }

    /^      id: / {
      current_provider = $0
      sub(/^      id: /, "", current_provider)
    }

    {
      print
    }

    current_provider == "openai" && /^      api_key_env: OPENAI_API_KEY$/ {
      print "      extra:"
      print "        allowed_models:"
      print "          - gpt-4o-mini"
      print "          - gpt-5.1"
      print "          - gpt-4.1-mini"
      print "          - gpt-4.1-nano"
    }

    current_provider == "vertexai" && /^        location: \$\{env.VERTEX_AI_LOCATION:=global\}$/ {
      print "        allowed_models:"
      print "          - publishers/google/models/gemini-2.5-pro"
      print "          - publishers/google/models/gemini-2.5-flash-lite"
      print "          - publishers/google/models/gemini-3.1-pro-preview"
      print "          - publishers/google/models/gemini-3.5-flash-lite"
    }
  '
}

inject_byok_rag() {
  awk '
    /^rag:$/ {
      print "byok_rag:"
      print "  - rag_id: custom-org-docs"
      print "    rag_type: inline::faiss"
      print "    embedding_model: nomic-ai/nomic-embed-text-v1.5"
      print "    embedding_dimension: 768"
      print "    vector_db_id: vs_727b6321-1ff4-47bf-a76b-1cc12426c954"
      print "    db_path: /tmp/vector_db/custom_docs/faiss_store.db"
      print "    score_multiplier: 1.0"
    }
    /^    - okp$/ {
      print "    - custom-org-docs"
    }
    { print }
  '
}

echo "Generating llama-stack ConfigMap..."
{
  cat << 'HEADER'
kind: ConfigMap
apiVersion: v1
metadata:
  name: llama-stack-config
  namespace: {{ .Release.Namespace }}
data:
  config.yaml: |
HEADER
  strip_license "${REPO_ROOT}/llama-stack-configs/config.yaml" \
    | indent
} > "${OUTPUT_DIR}/llama-stack-config.yaml"

echo "Generating lightspeed-stack ConfigMap..."
{
  cat << 'HEADER'
kind: ConfigMap
apiVersion: v1
metadata:
  name: lightspeed-stack-config
  namespace: {{ .Release.Namespace }}
data:
  lightspeed-stack.yaml: |
HEADER
  uncomment_inference_providers < "${REPO_ROOT}/lightspeed-core-configs/lightspeed-stack.yaml" \
    | strip_comments \
    | notebooks_vector_store_faiss_to_pgvector \
    | add_inference_allowed_models \
    | inject_byok_rag \
    | indent
} > "${OUTPUT_DIR}/lightspeed-stack-config.yaml"

echo "Generating rhdh-profile.py..."
cp "${REPO_ROOT}/lightspeed-core-configs/rhdh-profile.py" "${OUTPUT_DIR}/rhdh-profile.py"

echo "Updating lightspeed-core sidecar image in values.yaml..."
LIGHTSPEED_CORE_IMAGE="$(get_image "lightspeed-core")"
VALUES_YAML="${GITOPS_REPO}/charts/rhdh/values.yaml"
if [[ ! -f "${VALUES_YAML}" ]]; then
  echo "Error: ${VALUES_YAML} not found." >&2
  exit 1
fi
sed -i "s|image: [^ ]*/lightspeed-stack[^ ]*|image: ${LIGHTSPEED_CORE_IMAGE}|g" "${VALUES_YAML}"

echo "Generated manifests:"
ls -1 "${OUTPUT_DIR}"
