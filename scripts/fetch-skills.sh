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
SKILLS_DIR="$REPO_ROOT/skills"
RHDH_SKILLS_REPO="${RHDH_SKILLS_REPO:-https://github.com/redhat-developer/rhdh-skills.git}"
RHDH_SKILLS_REF="${RHDH_SKILLS_REF:-main}"

mkdir -p "$SKILLS_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Fetching RHDH skills from $RHDH_SKILLS_REPO (ref: $RHDH_SKILLS_REF)..."
git clone --depth 1 --branch "$RHDH_SKILLS_REF" "$RHDH_SKILLS_REPO" "$TMP_DIR/rhdh-skills"

if [ ! -d "$TMP_DIR/rhdh-skills/skills" ]; then
  echo "Error: no skills/ directory found in the rhdh-skills repository"
  exit 1
fi

# Clear existing skills (preserve .gitkeep)
find "$SKILLS_DIR" -mindepth 1 -not -name '.gitkeep' -exec rm -rf {} + 2>/dev/null || true

# Copy skill directories (category/skill-name/SKILL.md structure)
cp -R "$TMP_DIR/rhdh-skills/skills/"* "$SKILLS_DIR/"

SKILL_COUNT=$(find "$SKILLS_DIR" -name 'SKILL.md' | wc -l | tr -d ' ')
echo "Fetched $SKILL_COUNT skills into $SKILLS_DIR"
echo ""
echo "NOTE: Restart LCORE for the new skills to take effect:"
echo "  make local-down && make local-up"
