#!/usr/bin/env bash
# Idempotently merge dotfiles-managed Claude Code config keys into
# ~/.claude.json. Claude Code live-mutates that file, so we can't stow or
# symlink it — we reconcile the specific keys we care about instead.
set -euo pipefail

python3 - <<'PY'
import fcntl
import json
import os
import sys
from pathlib import Path

DESIRED = {
    "editorMode": "vim",
}

path = Path.home() / ".claude.json"

# Hold an exclusive flock on the file across the read-modify-write window
# so a concurrent claude write can't race our in-place truncate-and-write.
# When we are the one creating the file (session-token data), use
# O_CREAT|O_EXCL with 0o600 so claude can't slip a 0644 file under us
# between our exists()-check and create.
try:
    os.close(os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600))
except FileExistsError:
    pass
with path.open("r+", encoding="utf-8") as f:
    fcntl.flock(f.fileno(), fcntl.LOCK_EX)
    raw = f.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError as e:
        print(f"error: {path} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(data, dict):
        print(f"error: {path} is not a JSON object", file=sys.stderr)
        sys.exit(1)

    changed = [k for k, v in DESIRED.items() if data.get(k) != v]
    data.update(DESIRED)

    if changed:
        f.seek(0)
        f.truncate()
        f.write(json.dumps(data, indent=2) + "\n")
        print(f"updated {path}: set {', '.join(changed)}")
    else:
        print(f"{path}: already up to date")
    # flock released when f closes.
PY

# --- Claude Code plugins ---------------------------------------------------
# Install Claude Code plugins user-globally so they survive across all sessions
# (including every Lunar tab) without per-session boot work. Idempotent: skips
# when the marketplace is already registered and the plugin cache dir exists.

ensure_claude_plugin() {
    local source="$1" marketplace="$2" plugin="$3"
    if ! command -v claude >/dev/null 2>&1; then
        echo "claude CLI not on PATH — skipping ${plugin} install."
        return
    fi
    local known="$HOME/.claude/plugins/known_marketplaces.json"
    if ! grep -q "\"${marketplace}\"" "$known" 2>/dev/null; then
        echo "Adding Claude marketplace ${marketplace} from ${source}..."
        claude plugin marketplace add "$source"
    fi
    local cache="$HOME/.claude/plugins/cache/${marketplace}/${plugin}"
    if [[ ! -d "$cache" ]]; then
        echo "Installing Claude plugin ${plugin}@${marketplace}..."
        claude plugin install "${plugin}@${marketplace}" --scope user
    else
        echo "Claude plugin ${plugin}@${marketplace}: already installed."
    fi
}

# Each entry: <marketplace-source> <marketplace-name> <plugin-name>
# Marketplace source can be a github repo (owner/name), URL, or local path.
ensure_claude_plugin JuliusBrussee/caveman caveman caveman
