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

mkdir -p "${OUTPUT_DIR}"

indent() {
  sed 's/^/    /'
}

strip_license() {
  sed -n '/^[^#]/,$p' "$1"
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
    | sed 's/^name:.*/name: "lightspeed-core-stack"/' \
    | indent
  cat << 'MCP_SECTION'
    mcp_servers:
      - name: mcp-integration-tools
        provider_id: "model-context-protocol"
        url: "http://{{ .Release.Name }}-backstage.{{ .Release.Namespace }}.svc.cluster.local:7007/api/mcp-actions/v1"
        authorization_headers:
          Authorization: "client"
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

echo "Generated manifests:"
ls -1 "${OUTPUT_DIR}"
