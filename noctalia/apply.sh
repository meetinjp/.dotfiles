#!/usr/bin/env bash
# Idempotently pin the Noctalia colorscheme to Gruvbox. Noctalia live-mutates
# ~/.config/noctalia/settings.json (its settings UI rewrites it), so we can't
# stow or symlink it — we reconcile only the colorSchemes keys we care about,
# the same way claude/apply.sh reconciles ~/.claude.json. Everything else stays
# Noctalia's own runtime config. Linux desktop only (no Noctalia on macOS).
set -euo pipefail

[[ "$(uname -s)" == Darwin ]] && { echo "macOS — no Noctalia, skipping."; exit 0; }

python3 - <<'PY'
import fcntl
import json
import os
import sys
from pathlib import Path

# Only the keys we own. Noctalia fills the rest of colorSchemes with its
# defaults; we just force the scheme and keep wallpaper-derived colors off so
# the pinned scheme isn't overridden.
DESIRED = {
    "predefinedScheme": "Gruvbox",
    "useWallpaperColors": False,
}

path = Path.home() / ".config" / "noctalia" / "settings.json"
path.parent.mkdir(parents=True, exist_ok=True)

# Exclusive flock across read-modify-write so a concurrent Noctalia write can't
# race our truncate. O_CREAT|O_EXCL on first create keeps perms at 0600.
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

    cs = data.get("colorSchemes")
    if not isinstance(cs, dict):
        cs = {}
    changed = [k for k, v in DESIRED.items() if cs.get(k) != v]
    cs.update(DESIRED)
    data["colorSchemes"] = cs

    if changed:
        f.seek(0)
        f.truncate()
        f.write(json.dumps(data, indent=2) + "\n")
        print(f"updated {path}: colorSchemes {', '.join(changed)}")
    else:
        print(f"{path}: colorscheme already Gruvbox")
    # flock released when f closes.
PY

# If Noctalia is already running, apply the scheme live too (no relaunch needed).
# No-op on a fresh/headless box where the shell isn't up yet.
if command -v qs >/dev/null 2>&1; then
    qs -c noctalia-shell ipc call colorScheme set Gruvbox >/dev/null 2>&1 || true
fi
