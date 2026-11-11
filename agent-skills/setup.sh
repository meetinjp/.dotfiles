#!/usr/bin/env bash
# Optional shared agent configuration. One pinned source supplies both hosts.
set -euo pipefail
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
	echo "Usage: ./agent-skills/setup.sh"
	echo "Configure shared skills, agent preferences, and personal Claude skills."
	exit 0
fi
[[ $# == 0 ]] || { echo "Unexpected argument: $1" >&2; exit 2; }
git -C "$DOTFILES" submodule update --init agent-skills/caveman
"$DOTFILES/codex/apply.sh"
python3 "$DOTFILES/agent-skills/apply.py"
"$DOTFILES/claude/apply.sh"
"$DOTFILES/install.sh" --profile agents
