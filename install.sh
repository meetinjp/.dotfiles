#!/usr/bin/env bash
set -euo pipefail

# perl (used by stow) spams locale warnings if LANG points at an
# ungenerated locale. Force a locale that's always built into glibc so
# the install output stays clean. setup.sh handles the proper fix
# (running locale-gen for en_US.UTF-8).
export LC_ALL=C.UTF-8 LANG=C.UTF-8

if ! command -v stow &>/dev/null; then
	echo "stow not found. Install GNU stow and rerun." >&2
	exit 1
fi

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOW_DIRS="hyprland nvim prettier tofi waybar wezterm zsh"

echo "Installing dotfiles..."

pushd "$DOTFILES" >/dev/null

for dir in $STOW_DIRS; do
	stow -D "$dir"
	stow "$dir"
done

popd >/dev/null

# Claude Code config — patched rather than stowed since ~/.claude.json is
# live-mutated by Claude itself.
"$DOTFILES/claude/apply.sh"

echo "Dotfiles installed successfully!"
