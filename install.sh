#!/usr/bin/env bash

# perl (used by stow) spams locale warnings if LANG points at an
# ungenerated locale. Force a locale that's always built into glibc so
# the install output stays clean. setup.sh handles the proper fix
# (running locale-gen for en_US.UTF-8).
export LC_ALL=C.UTF-8 LANG=C.UTF-8

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

# wezterm runs on the Windows host, not in WSL — push the config to the
# Windows-side %USERPROFILE%\.config\wezterm so it works without also
# running install.ps1. cp -f keeps this idempotent. install.ps1 has the
# matching junction logic for Windows-native clones.
#
# We avoid invoking cmd.exe because WSL interop binfmt isn't always
# registered (notably under systemd=true on some setups). Instead we
# scan /mnt/c/Users/ for a real user home: case-insensitive match
# against $USER first, then any dir with AppData\Local that isn't a
# system pseudo-user.
if [[ -n "${WSL_DISTRO_NAME:-}" && -d /mnt/c/Users ]]; then
	find_win_home() {
		local me="${USER,,}" base
		for d in /mnt/c/Users/*/; do
			base="$(basename "$d")"
			case "${base,,}" in public|default|"default user"|"all users"|devtoolsuser) continue ;; esac
			if [[ "${base,,}" == "$me" ]]; then echo "${d%/}"; return; fi
		done
		for d in /mnt/c/Users/*/; do
			base="$(basename "$d")"
			case "${base,,}" in public|default|"default user"|"all users"|devtoolsuser) continue ;; esac
			[[ -d "$d/AppData/Local" ]] && { echo "${d%/}"; return; }
		done
	}
	WIN_HOME="$(find_win_home)"
	if [[ -n "$WIN_HOME" ]]; then
		WIN_WEZTERM="$WIN_HOME/.config/wezterm"
		mkdir -p "$WIN_WEZTERM"
		cp -f "$DOTFILES/wezterm/.config/wezterm/wezterm.lua" "$WIN_WEZTERM/wezterm.lua"
		echo "wezterm: copied to $WIN_WEZTERM/wezterm.lua"
	else
		echo "wezterm: could not locate Windows user home under /mnt/c/Users — skipped"
	fi
fi

# gminds — separate (eventually public) repo, brought in as a submodule.
# Delegates to its own installer so the install logic lives with the tool.
if [[ -f "$DOTFILES/gminds/install.sh" ]]; then
    bash "$DOTFILES/gminds/install.sh"
else
    echo "gminds submodule missing — run: git submodule update --init"
fi

echo "Dotfiles installed successfully!"
