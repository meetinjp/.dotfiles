#!/usr/bin/env bash

DOTFILES="$(dirname "${BASH_SOURCE[0]}")"
STOW_DIRS="hyprland kitty nvim prettier tofi waybar zsh"

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

# gminds — separate (eventually public) repo, brought in as a submodule.
# Delegates to its own installer so the install logic lives with the tool.
if [[ -f "$DOTFILES/gminds/install.sh" ]]; then
    bash "$DOTFILES/gminds/install.sh"
else
    echo "gminds submodule missing — run: git submodule update --init"
fi

echo "Dotfiles installed successfully!"
