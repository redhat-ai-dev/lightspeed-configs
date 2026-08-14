#!/usr/bin/env python3
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

from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_FILE = REPO_ROOT / "lightspeed-core-configs" / "rhdh-profile.py"
TARGET_FILE = REPO_ROOT / "lightspeed-core-configs" / "lightspeed-stack.yaml"
PROMPT_PLACEHOLDER_REPLACEMENTS = {
    "{SUBJECT_ALLOWED}": "${allowed}",
    "{SUBJECT_REJECTED}": "${rejected}",
    # Profile f-string uses ${{message}} so the runtime string is ${message};
    # YAML gets the Template form directly.
    "${{message}}": "${message}",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sync question-validation prompt templates into lightspeed-stack.yaml "
            "(LCORE shields.question_validity)."
        )
    )
    parser.add_argument(
        "mode",
        nargs="?",
        choices=("update", "validate"),
        default="update",
        help=(
            "Whether to update lightspeed-stack.yaml or validate it is already "
            "in sync."
        ),
    )
    return parser.parse_args()


def extract_triple_quoted(
    source_text: str, name: str, *, is_fstring: bool = False
) -> str:
    prefix = "f" if is_fstring else ""
    pattern = rf"^{name}\s*=\s*{prefix}\"\"\"\n(.*?)\n\"\"\""
    match = re.search(pattern, source_text, flags=re.MULTILINE | re.DOTALL)
    if not match:
        raise SystemExit(f"Could not find {name} in {SOURCE_FILE}")

    lines = match.group(1).splitlines()
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


def render_yaml_block(indent: str, key: str, value: str) -> str:
    rendered_lines = []
    for line in value.splitlines():
        rendered_lines.append(f"{indent}  {line}" if line else "")
    return f"{indent}{key}: |-\n" + "\n".join(rendered_lines) + "\n"


def replace_section(text: str, pattern: str, key: str, value: str) -> str:
    match = re.search(pattern, text, flags=re.MULTILINE | re.DOTALL)
    if not match:
        raise SystemExit(f"Could not find YAML block for {key} in {TARGET_FILE}")

    indent = match.group("indent")
    replacement = render_yaml_block(indent, key, value)
    return text[: match.start()] + replacement + text[match.end() :]


def build_updated_text(source_text: str, target_text: str) -> str:
    model_prompt = extract_triple_quoted(
        source_text, "QUESTION_VALIDATOR_PROMPT_TEMPLATE", is_fstring=True
    )
    for source_value, target_value in PROMPT_PLACEHOLDER_REPLACEMENTS.items():
        model_prompt = model_prompt.replace(source_value, target_value)

    invalid_response = extract_triple_quoted(source_text, "INVALID_QUERY_RESP")

    updated_text = replace_section(
        target_text,
        r"^(?P<indent>\s*)model_prompt: \|-\n.*?(?=^(?P=indent)invalid_question_response: \|-)",
        "model_prompt",
        model_prompt,
    )
    updated_text = replace_section(
        updated_text,
        r"^(?P<indent>\s*)invalid_question_response: \|-\n.*?(?=^skills:|^mcp_servers:)",
        "invalid_question_response",
        invalid_response,
    )

    return updated_text


def print_diff(current_text: str, expected_text: str) -> None:
    diff = difflib.unified_diff(
        current_text.splitlines(keepends=True),
        expected_text.splitlines(keepends=True),
        fromfile=str(TARGET_FILE),
        tofile=f"{TARGET_FILE} (expected)",
    )
    sys.stdout.writelines(diff)


def main() -> int:
    args = parse_args()
    source_text = SOURCE_FILE.read_text(encoding="utf-8")
    target_text = TARGET_FILE.read_text(encoding="utf-8")
    updated_text = build_updated_text(source_text, target_text)

    if target_text == updated_text:
        print("Prompt templates are in sync.")
        return 0

    if args.mode == "validate":
        print(
            "Prompt templates in lightspeed-core-configs/lightspeed-stack.yaml "
            "are out of sync with lightspeed-core-configs/rhdh-profile.py."
        )
        print_diff(target_text, updated_text)
        print("")
        print("Run 'make update-prompt-templates' to fix.")
        return 1

    TARGET_FILE.write_text(updated_text, encoding="utf-8")
    print(
        "Updated lightspeed-core-configs/lightspeed-stack.yaml from "
        "lightspeed-core-configs/rhdh-profile.py"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
