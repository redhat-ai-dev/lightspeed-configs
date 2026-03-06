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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/lightspeed-core-configs/lightspeed-stack.yaml"
TARGET="$REPO_ROOT/compose/lightspeed-stack.compose.yaml"
COMPOSE_LLAMA_STACK_URL="http://llama-stack:8321"

command -v yq >/dev/null 2>&1 || {
  echo "Error: yq is required. Install from https://github.com/mikefarah/yq"
  exit 1
}

expected="$(yq ".llama_stack.url = \"$COMPOSE_LLAMA_STACK_URL\" | ... comments = \"\"" "$SOURCE")"
actual="$(yq '... comments = ""' "$TARGET")"

if [ "$expected" != "$actual" ]; then
  echo "MISMATCH: compose/lightspeed-stack.compose.yaml is out of sync with lightspeed-core-configs/lightspeed-stack.yaml"
  echo ""
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
  echo ""
  echo "Run 'make sync-compose-config' to fix."
  exit 1
fi
echo "Compose config in sync."
