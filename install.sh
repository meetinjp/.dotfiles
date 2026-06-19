#!/usr/bin/env bash
set -euo pipefail

is_macos() { [[ "$(uname -s)" == Darwin ]]; }

# perl (used by stow) spams locale warnings if LANG points at an ungenerated
# locale. Force one that always exists: glibc ships C.UTF-8; macOS/BSD libc
# does not, but always ships en_US.UTF-8. setup.sh handles the proper Linux
# fix (running locale-gen for en_US.UTF-8).
if is_macos; then
	export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
else
	export LC_ALL=C.UTF-8 LANG=C.UTF-8
fi

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# macOS: install the Homebrew package set first (the pacman-list analog). This
# also provides `stow` itself, so it must run before the stow check below. On
# Linux, packages come from pacman (see README) — brew is absent and skipped.
if is_macos && command -v brew &>/dev/null; then
	echo "Installing Homebrew packages (brew bundle)..."
	brew bundle --file="$DOTFILES/Brewfile" || \
		echo "  brew bundle reported errors — continuing (rerun it manually if needed)."
fi

if ! command -v stow &>/dev/null; then
	echo "stow not found. Install GNU stow and rerun." >&2
	echo "  macOS: brew bundle --file=$DOTFILES/Brewfile   |   Linux: sudo pacman -S stow" >&2
	exit 1
fi

# Each entry is a stow package — its contents are symlinked into $HOME.
# Note: getty@tty1 autologin override lives at /etc/systemd/system/... and
# is sudo-installed by setup.sh, not stowed.
#
# Split by OS. COMMON stows everywhere. LINUX_ONLY is the Wayland desktop
# (niri, kanshi), the niri-session-anchor systemd user unit, the bin/ helper
# script (niri-screenshot, Linux-only), and firefox (its XDG path is wrong on
# macOS, so the macOS branch links user.js into ~/Library instead of stowing).
COMMON_DIRS=(
	ghostty
	nvim
	prettier
	ripgrep
	ruby
	starship
	tmux
	zsh
)
LINUX_ONLY_DIRS=(
	bin
	firefox
	kanshi
	niri
	systemd
)
if is_macos; then
	STOW_DIRS=("${COMMON_DIRS[@]}")
else
	STOW_DIRS=("${COMMON_DIRS[@]}" "${LINUX_ONLY_DIRS[@]}")
fi

echo "Installing dotfiles..."

# The ruby package stows a single file into rbenv's root (~/.rbenv/default-gems).
# If ~/.rbenv doesn't exist yet, stow would "tree-fold" and symlink the WHOLE
# ~/.rbenv to the repo — then `rbenv install` would write compiled Rubies into
# the git tree. Pre-creating the real dir forces stow to fold into it and link
# only the leaf file. Idempotent.
mkdir -p "$HOME/.rbenv"

# Same tree-fold guard for systemd user units (Linux only): pre-create the real
# dir so stow links only the leaf .service file in, instead of symlinking the
# whole ~/.config/systemd/user into the repo — which would trap any future
# `systemctl --user enable` wants/ symlinks inside the git tree.
if ! is_macos; then
	mkdir -p "$HOME/.config/systemd/user"
fi

# The nvim config is a git submodule with an SSH remote. On a fresh box the SSH
# key isn't on GitHub yet, so a plain `git clone` (or one without --recursive)
# leaves nvim/.config/nvim empty — and nvim then loads its bare defaults. Init it
# over HTTPS via insteadOf so it works before the key is uploaded. Idempotent:
# skips once the submodule's init.lua is present.
if [[ -f "$DOTFILES/.gitmodules" && ! -e "$DOTFILES/nvim/.config/nvim/init.lua" ]]; then
	echo "Initialising git submodules (nvim config) over HTTPS..."
	git -C "$DOTFILES" -c url."https://github.com/".insteadOf="git@github.com:" \
		submodule update --init --recursive \
		|| echo "  submodule init failed — rerun once your SSH key is on GitHub."
fi

pushd "$DOTFILES" >/dev/null

for dir in "${STOW_DIRS[@]}"; do
	stow -D "$dir"
	stow "$dir"
done

popd >/dev/null

# Make any freshly-stowed systemd user units (e.g. niri-session-anchor.service)
# visible to the running user manager without a relogin. No-op if the user
# manager isn't up (e.g. provisioning over SSH).
if ! is_macos && command -v systemctl &>/dev/null; then
	systemctl --user daemon-reload 2>/dev/null || true
fi

# Claude Code config — patched rather than stowed since ~/.claude.json is
# live-mutated by Claude itself.
"$DOTFILES/claude/apply.sh"

# Noctalia colorscheme — patched rather than stowed since Noctalia live-mutates
# its settings.json. Pins the Gruvbox scheme; Linux-only (no-op on macOS).
"$DOTFILES/noctalia/apply.sh"

# macOS-only deployment for paths stow can't express (they live outside
# ~/.config). Idempotent — safe to rerun.
if is_macos; then
	# Firefox: the firefox/ package mirrors the Linux XDG path
	# (~/.config/mozilla/firefox), which macOS Firefox never reads. Symlink
	# user.js into the real macOS profile dir instead. The profile hash is
	# per-install, so locate the dev-edition profile at runtime.
	ff_profiles="$HOME/Library/Application Support/Firefox/Profiles"
	ff_src="$(find "$DOTFILES/firefox" -name user.js -print -quit 2>/dev/null || true)"
	if [[ -z "$ff_src" ]]; then
		echo "  firefox: no user.js in repo — skipping."
	elif [[ ! -d "$ff_profiles" ]]; then
		echo "  firefox: $ff_profiles missing — launch Firefox Developer Edition once, then rerun."
	else
		ff_prof="$(find "$ff_profiles" -maxdepth 1 -type d -name '*.dev-edition-default' -print -quit 2>/dev/null || true)"
		if [[ -z "$ff_prof" ]]; then
			echo "  firefox: no *.dev-edition-default profile yet — launch FDE once, then rerun."
		else
			# Back up a pre-existing real user.js (not our own symlink) so a
			# hand-rolled one is never silently clobbered.
			if [[ -e "$ff_prof/user.js" && ! -L "$ff_prof/user.js" ]]; then
				mv "$ff_prof/user.js" "$ff_prof/user.js.bak.$(date +%s)"
				echo "  firefox: backed up existing user.js → user.js.bak.*"
			fi
			ln -sfn "$ff_src" "$ff_prof/user.js"
			echo "  firefox: linked user.js → $ff_prof/user.js"
		fi
	fi

	# Ghostty: layer the macOS overrides (cmd-key idioms, native titlebar,
	# quick-terminal rebind) on top of the shared base config. Ghostty reads
	# the stowed ~/.config/ghostty/config first, then the Application Support
	# config — so an include placed there loads last and wins, without editing
	# the shared base config that Linux uses.
	ghostty_app_dir="$HOME/Library/Application Support/com.mitchellh.ghostty"
	ghostty_app_cfg="$ghostty_app_dir/config"
	ghostty_include="config-file = $HOME/.config/ghostty/config-macos.conf"
	mkdir -p "$ghostty_app_dir"
	if ! grep -qF "$ghostty_include" "$ghostty_app_cfg" 2>/dev/null; then
		printf '%s\n' "$ghostty_include" >> "$ghostty_app_cfg"
		echo "  ghostty: enabled macOS override include in $ghostty_app_cfg"
	else
		echo "  ghostty: macOS override include already present."
	fi
fi

echo "Dotfiles installed successfully!"
