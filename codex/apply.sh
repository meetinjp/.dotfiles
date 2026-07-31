#!/usr/bin/env bash
# Reconcile dotfiles-managed defaults into the active Codex state directory
# without replacing live-mutated auth, project trust, session, marketplace,
# or plugin state.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_CONFIG_DIR="${CODEX_DOTFILES_TARGET_DIR:-${CODEX_HOME:-$HOME/.codex}}"
CODEX_CONFIG_PATH="$CODEX_CONFIG_DIR/config.toml"

mkdir -p "$CODEX_CONFIG_DIR"

if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 not on PATH — cannot patch $CODEX_CONFIG_PATH." >&2
	exit 1
fi

export CODEX_DOTFILES_CONFIG_PATH="$CODEX_CONFIG_PATH"
python3 - <<'PY'
import datetime
import fcntl
import json
import math
import os
import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    print("error: Codex config reconciliation requires Python 3.11 or newer", file=sys.stderr)
    sys.exit(1)

DESIRED = {
    None: {
        "model": '"gpt-5.6-sol"',
        "model_reasoning_effort": '"xhigh"',
        "personality": '"pragmatic"',
    },
    "tui": {
        "vim_mode_default": "true",
        "alternate_screen": '"always"',
        "notifications": '["agent-turn-complete", "approval-requested"]',
        "notification_method": '"auto"',
        "notification_condition": '"unfocused"',
        "status_line": '["model-with-reasoning", "context-remaining", "git-branch"]',
    },
    "mcp_servers.openaiDeveloperDocs": {
        "url": '"https://developers.openai.com/mcp"',
    },
}

path = Path(os.environ["CODEX_DOTFILES_CONFIG_PATH"])
path.parent.mkdir(parents=True, exist_ok=True)

try:
    os.close(os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600))
except FileExistsError:
    pass

MARKER_KEY = "__codex_dotfiles_marker__"
BARE_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def marker_path(node, path=()):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == MARKER_KEY and value == 0:
                return path
            found = marker_path(value, path + (key,))
            if found is not None:
                return found
    elif isinstance(node, list):
        for value in node:
            found = marker_path(value, path)
            if found is not None:
                return found
    return None


def table_header(line):
    stripped = line.lstrip()
    if not stripped.startswith("["):
        return None

    try:
        parsed = tomllib.loads(f"{line.rstrip()}\n{MARKER_KEY} = 0\n")
    except tomllib.TOMLDecodeError:
        return None

    path = marker_path(parsed)
    if path is None:
        return None
    return path, stripped.startswith("[[")


def assignment_key(line):
    quote = None
    escaped = False
    for index, char in enumerate(line):
        if quote == '"':
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quote = None
            continue
        if quote == "'":
            if char == "'":
                quote = None
            continue
        if char in ('"', "'"):
            quote = char
        elif char == "#":
            return None
        elif char == "=":
            expression = line[:index].strip()
            if not expression:
                return None
            try:
                parsed = tomllib.loads(f"{expression} = 0\n")
            except tomllib.TOMLDecodeError:
                return None

            path = []
            node = parsed
            while isinstance(node, dict) and len(node) == 1:
                key, node = next(iter(node.items()))
                path.append(key)
            if node == 0:
                return tuple(path), expression
            return None
    return None


def scan_document(lines):
    current_table = ()
    assignments = []
    headers = []
    index = 0
    while index < len(lines):
        line = lines[index]
        header = table_header(line)
        if header is not None:
            current_table = header[0]
            headers.append((header[0], index, header[1]))
            index += 1
            continue

        key = assignment_key(line)
        if key is not None:
            assignments.append((current_table + key[0], index, key[1]))
            neutral_replacement = f"{key[1]} = 0\n"
            index = complete_value_span_end(lines, index, neutral_replacement)
        else:
            index += 1
    return assignments, headers


def render_key_path(path):
    if not all(BARE_KEY_RE.fullmatch(component) for component in path):
        raise ValueError(f"managed TOML path contains a non-bare key: {path!r}")
    return ".".join(path)


def render_toml_key(key):
    return key if BARE_KEY_RE.fullmatch(key) else json.dumps(key, ensure_ascii=False)


def render_toml_value(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value):
            return "nan"
        if math.isinf(value):
            return "-inf" if value < 0 else "inf"
        return repr(value)
    if isinstance(value, (datetime.datetime, datetime.date, datetime.time)):
        return value.isoformat()
    if isinstance(value, list):
        return "[" + ", ".join(render_toml_value(item) for item in value) + "]"
    if isinstance(value, dict):
        entries = (
            f"{render_toml_key(key)} = {render_toml_value(item)}"
            for key, item in value.items()
        )
        return "{ " + ", ".join(entries) + " }"
    raise TypeError(f"unsupported TOML value type: {type(value).__name__}")


def value_at_path(document, path):
    value = document
    for component in path:
        if not isinstance(value, dict) or component not in value:
            return None
        value = value[component]
    return value


def complete_value_span_end(lines, start, replacement):
    """Return the end of the existing TOML value without consuming the next table."""
    for candidate_end in range(start + 1, len(lines) + 1):
        candidate_lines = lines[:start] + [replacement] + lines[candidate_end:]
        try:
            tomllib.loads("".join(candidate_lines))
        except tomllib.TOMLDecodeError:
            continue
        return candidate_end

    raise ValueError(f"could not determine the complete TOML value at line {start + 1}")


def reconcile_inline_ancestor(lines, assignments, target, value):
    document = tomllib.loads("".join(lines))
    candidates = sorted(
        (
            assignment
            for assignment in assignments
            if len(assignment[0]) < len(target)
            and target[: len(assignment[0])] == assignment[0]
        ),
        key=lambda assignment: len(assignment[0]),
        reverse=True,
    )

    for ancestor_path, index, expression in candidates:
        ancestor = value_at_path(document, ancestor_path)
        if not isinstance(ancestor, dict):
            continue

        relative_path = target[len(ancestor_path) :]
        cursor = ancestor
        for component in relative_path[:-1]:
            if component not in cursor:
                cursor[component] = {}
            elif not isinstance(cursor[component], dict):
                raise ValueError(
                    f"cannot reconcile {'.'.join(target)} through non-table "
                    f"{'.'.join(ancestor_path + (component,))}"
                )
            cursor = cursor[component]

        desired_value = tomllib.loads(f"value = {value}\n")["value"]
        cursor[relative_path[-1]] = desired_value
        replacement = f"{expression} = {render_toml_value(ancestor)}\n"
        value_end = complete_value_span_end(lines, index, replacement)
        if value_end == index + 1 and lines[index] == replacement:
            return False
        lines[index:value_end] = [replacement]
        return True

    return None


def set_value(lines, section, key, value):
    target = tuple(section.split(".")) + (key,) if section else (key,)
    assignments, headers = scan_document(lines)

    for assignment_path, index, expression in assignments:
        if assignment_path != target:
            continue
        replacement = f"{expression} = {value}\n"
        value_end = complete_value_span_end(lines, index, replacement)
        if value_end == index + 1 and lines[index] == replacement:
            return False
        lines[index:value_end] = [replacement]
        return True

    inline_changed = reconcile_inline_ancestor(lines, assignments, target, value)
    if inline_changed is not None:
        return inline_changed

    table_path = target[:-1]
    candidates = [
        header
        for header in headers
        if not header[2]
        and len(header[0]) <= len(table_path)
        and target[: len(header[0])] == header[0]
    ]
    if candidates:
        selected_path, selected_index, _ = max(
            candidates, key=lambda header: (len(header[0]), header[1])
        )
        insertion = next(
            (header[1] for header in headers if header[1] > selected_index),
            len(lines),
        )
        relative_path = target[len(selected_path) :]
    else:
        insertion = headers[0][1] if headers else len(lines)
        relative_path = target

    replacement = f"{render_key_path(relative_path)} = {value}\n"
    lines.insert(insertion, replacement)
    return True


with path.open("r+", encoding="utf-8") as config_file:
    fcntl.flock(config_file.fileno(), fcntl.LOCK_EX)
    raw = config_file.read()
    try:
        tomllib.loads(raw)
    except tomllib.TOMLDecodeError as error:
        print(f"error: {path} is not valid TOML: {error}", file=sys.stderr)
        sys.exit(1)

    lines = raw.splitlines(keepends=True)
    if lines and not lines[-1].endswith(("\n", "\r")):
        lines[-1] += "\n"
    changed = []
    for section, values in DESIRED.items():
        for key, value in values.items():
            if set_value(lines, section, key, value):
                changed.append(f"{section + '.' if section else ''}{key}")

    patched = "".join(lines)
    try:
        tomllib.loads(patched)
    except tomllib.TOMLDecodeError as error:
        print(f"error: generated invalid TOML for {path}: {error}", file=sys.stderr)
        sys.exit(1)

    if changed:
        config_file.seek(0)
        config_file.truncate()
        config_file.write(patched)
        config_file.flush()
        os.fsync(config_file.fileno())
        print(f"updated {path}: set {', '.join(changed)}")
    else:
        print(f"{path}: already up to date")
PY
unset CODEX_DOTFILES_CONFIG_PATH

# Global guidance is static, so keep it as a visible dotfiles symlink. Preserve
# a pre-existing real file as a timestamped backup rather than overwriting it.
managed_agents="$DOTFILES/codex/AGENTS.md"
global_agents="$CODEX_CONFIG_DIR/AGENTS.md"
if [[ -L "$global_agents" && "$(readlink "$global_agents")" == "$managed_agents" ]]; then
	echo "$global_agents: already linked"
else
	if [[ -e "$global_agents" || -L "$global_agents" ]]; then
		backup="$global_agents.bak.$(date +%s)"
		mv "$global_agents" "$backup"
		echo "backed up $global_agents -> $backup"
	fi
	ln -s "$managed_agents" "$global_agents"
	echo "linked $global_agents -> $managed_agents"
fi

# Tests can target a temporary config directory without touching the real Codex
# plugin registry. Normal installs register this repo's marketplace and install
# the native caveman bundle globally.
if [[ -n "${CODEX_DOTFILES_TARGET_DIR:-}" || "${CODEX_APPLY_SKIP_PLUGINS:-0}" == 1 ]]; then
	echo "Codex plugin setup skipped."
elif ! command -v codex >/dev/null 2>&1; then
	echo "codex CLI not on PATH — skipping caveman plugin install."
elif ! codex plugin marketplace add "$DOTFILES" --json >/dev/null; then
	echo "warning: failed to register dotfiles Codex marketplace." >&2
elif codex plugin list --json | python3 -c '
import json, sys
data = json.load(sys.stdin)
raise SystemExit(0 if any(item.get("pluginId") == "caveman@dotfiles" for item in data.get("installed", [])) else 1)
'; then
	echo "Codex plugin caveman@dotfiles: already installed."
elif codex plugin add caveman@dotfiles --json >/dev/null; then
	echo "Installed Codex plugin caveman@dotfiles."
else
	echo "warning: failed to install Codex plugin caveman@dotfiles." >&2
fi
