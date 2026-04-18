#!/usr/bin/env bash

DOTFILES="$(dirname "${BASH_SOURCE[0]}")"
STOW_DIRS="hyprland kitty nvim tofi waybar zsh prettier"

echo "Installing dotfiles..."

pushd "$DOTFILES" >/dev/null

for dir in $STOW_DIRS; do
	stow -D "$dir"
	stow "$dir"
done

popd >/dev/null

echo "Dotfiles installed successfully!"
