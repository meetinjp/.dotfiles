#!/usr/bin/env bash
# Optional Codex sleep protection; ordinary desktop linking does not enable it.
set -euo pipefail
case "${1:-}" in
	--help|-h) echo "Usage: ./noctalia/setup-work-keep-awake.sh"; exit 0 ;;
	'') ;;
	*) echo "Unexpected argument: $1" >&2; exit 2 ;;
esac
[[ "$(uname -s)" == Linux ]] || { echo "Linux is required." >&2; exit 1; }
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
systemctl --user show-environment >/dev/null
"$DOTFILES/install.sh" bin systemd
"$DOTFILES/noctalia/apply-work-keep-awake.sh"
systemctl --user daemon-reload
systemctl --user enable --now work-keep-awake.service
echo "Sleep protection enabled. Reload Noctalia once after first installation."
