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
IMAGES_FILE="$REPO_ROOT/images.yaml"
ENV_FILE="$REPO_ROOT/env/default-values.env"

command -v yq >/dev/null 2>&1 || {
  echo "Error: yq is required. Install from https://github.com/mikefarah/yq"
  exit 1
}

declare -A KEY_TO_VAR=(
  ["lightspeed-core"]="LIGHTSPEED_CORE_IMAGE"
  ["llama-stack"]="LLAMA_STACK_IMAGE"
  ["rag-content"]="RAG_CONTENT_IMAGE"
)

contents="$(cat "$ENV_FILE")"

for key in "${!KEY_TO_VAR[@]}"; do
  var="${KEY_TO_VAR[$key]}"
  val="$(yq ".\"$key\".image" "$IMAGES_FILE")"
  contents="$(printf '%s\n' "$contents" | awk -v var="$var" -v val="$val" \
    'BEGIN{FS=OFS="="} $1==var{$2=val} {print}')"
done

printf '%s\n' "$contents" > "$ENV_FILE"
echo "default-values.env updated from images.yaml"
