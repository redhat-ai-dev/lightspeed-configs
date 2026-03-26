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

get_image() {
  local key="$1"
  awk -v key="${key}" '
    /^[^[:space:]]/ { in_section = ($0 == key":") }
    in_section && /^[[:space:]]+image:/ { print $2; exit }
  ' "${REPO_ROOT}/images.yaml"
}

echo "Generating lightspeed-stack ConfigMap..."
{
  cat << 'HEADER'
kind: ConfigMap
apiVersion: v1
metadata:
  name: lightspeed-stack
  namespace: {{ .Release.Namespace }}
data:
  lightspeed-stack.yaml: |
HEADER
  strip_license "${REPO_ROOT}/lightspeed-core-configs/lightspeed-stack.yaml" \
    | indent
  cat << 'MCP_SECTION'
    mcp_servers:
      - name: mcp-integration-tools
        provider_id: "model-context-protocol"
        url: "http://{{ .Release.Name }}-backstage.{{ .Release.Namespace }}.svc.cluster.local:7007/api/mcp-actions/v1"
        authorization_headers:
          Authorization: "/app-root/lightspeed-stack/mcp-auth-token"
MCP_SECTION
} > "${OUTPUT_DIR}/lightspeed-stack-config.yaml"

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
    | awk '/api_key: \$\{env\.OPENAI_API_KEY:=\}/ {
        print
        print "        allowed_models:"
        print "          - gpt-4o-mini"
        print "          - gpt-5.1"
        print "          - gpt-4.1-mini"
        print "          - gpt-4.1-nano"
        next
      }
      { print }' \
    | indent
} > "${OUTPUT_DIR}/llama-stack-config.yaml"

echo "Generating rhdh-profile.py..."
cp "${REPO_ROOT}/lightspeed-core-configs/rhdh-profile.py" "${OUTPUT_DIR}/rhdh-profile.py"

echo "Generating rolling-demo-sidecars-job.yaml with updated images..."
SIDECARS_JOB_SRC="${GITOPS_REPO}/charts/rhdh/templates/rolling-demo-sidecars-job.yaml"
if [[ ! -f "${SIDECARS_JOB_SRC}" ]]; then
  echo "Error: ${SIDECARS_JOB_SRC} not found. Set GITOPS_REPO to your ai-rolling-demo-gitops checkout." >&2
  exit 1
fi

LLAMA_STACK_IMAGE="$(get_image "llama-stack")"
LIGHTSPEED_CORE_IMAGE="$(get_image "lightspeed-core")"
RAG_CONTENT_IMAGE="$(get_image "rag-content")"

sed \
  -e "s|\"image\": \"[^\"]*/llama-stack[^\"]*\"|\"image\": \"${LLAMA_STACK_IMAGE}\"|g" \
  -e "s|\"image\": \"[^\"]*/lightspeed-stack[^\"]*\"|\"image\": \"${LIGHTSPEED_CORE_IMAGE}\"|g" \
  -e "s|\"image\": \"[^\"]*/rag-content[^\"]*\"|\"image\": \"${RAG_CONTENT_IMAGE}\"|g" \
  "${SIDECARS_JOB_SRC}" > "${OUTPUT_DIR}/rolling-demo-sidecars-job.yaml"

echo "Generated manifests:"
ls -1 "${OUTPUT_DIR}"
