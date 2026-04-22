#!/usr/bin/env bash
# Idempotently merge dotfiles-managed Claude Code config keys into
# ~/.claude.json. Claude Code live-mutates that file, so we can't stow or
# symlink it — we reconcile the specific keys we care about instead.
set -euo pipefail

python3 - <<'PY'
import json
import sys
from pathlib import Path

DESIRED = {
    "editorMode": "vim",
}

path = Path.home() / ".claude.json"
try:
    data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
except json.JSONDecodeError as e:
    print(f"error: {path} is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data, dict):
    print(f"error: {path} is not a JSON object", file=sys.stderr)
    sys.exit(1)

changed = [k for k, v in DESIRED.items() if data.get(k) != v]
data.update(DESIRED)

if changed:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    tmp.replace(path)
    print(f"updated {path}: set {', '.join(changed)}")
else:
    print(f"{path}: already up to date")
PY
