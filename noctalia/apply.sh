#!/usr/bin/env bash
# Idempotently pin the Noctalia colorscheme and conservative idle timeouts.
# Noctalia live-mutates
# ~/.config/noctalia/settings.json (its settings UI rewrites it), so we can't
# stow or symlink it — we reconcile only the settings we care about,
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

# Only the keys we own. Noctalia fills the remaining settings with defaults.
# Timeouts are seconds since the last input, not delays between stages.
DESIRED = {
    "colorSchemes": {
        "predefinedScheme": "Gruvbox",
        "useWallpaperColors": False,
    },
    "idle": {
        "enabled": True,
        "screenOffTimeout": 1200,
        "lockTimeout": 1500,
        "suspendTimeout": 3600,
        "fadeDuration": 10,
    },
    "general": {
        "lockOnSuspend": True,
    },
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

    changed = []
    for section, desired in DESIRED.items():
        current = data.get(section)
        if not isinstance(current, dict):
            current = {}
        changed.extend(
            f"{section}.{key}"
            for key, value in desired.items()
            if current.get(key) != value
        )
        current.update(desired)
        data[section] = current

    if changed:
        f.seek(0)
        f.truncate()
        f.write(json.dumps(data, indent=2) + "\n")
        print(f"updated {path}: {', '.join(changed)}")
    else:
        print(f"{path}: colorscheme and idle settings already applied")
    # flock released when f closes.
PY

# If Noctalia is already running, apply the scheme live too (no relaunch needed).
# No-op on a fresh/headless box where the shell isn't up yet.
if command -v qs >/dev/null 2>&1; then
    qs -c noctalia-shell ipc call colorScheme set Gruvbox >/dev/null 2>&1 || true
fi
