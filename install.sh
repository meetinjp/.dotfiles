#!/usr/bin/env bash
set -euo pipefail

is_macos()   { [[ "$(uname -s)" == Darwin ]]; }
# Distro family via /etc/os-release. CachyOS reports ID_LIKE=arch; TUXEDO OS
# reports ID=ubuntu (ID_LIKE=debian). macOS matches neither.
is_debian()  { [[ "$(uname -s)" == Linux ]] && grep -qiE '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release 2>/dev/null; }
is_arch()    { [[ "$(uname -s)" == Linux ]] && grep -qiE '^(ID|ID_LIKE)=.*arch' /etc/os-release 2>/dev/null; }
# Git for Windows' bash reports MINGW64_NT-...; plain MSYS2 reports MSYS_NT-...
is_windows() { [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; }

# perl (used by stow) spams locale warnings if LANG points at an ungenerated
# locale. Force one that always exists: glibc ships C.UTF-8; macOS/BSD libc
# does not, but always ships en_US.UTF-8. setup.sh handles the proper Linux
# fix (running locale-gen for en_US.UTF-8).
if is_macos; then
	export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
else
	export LC_ALL=C.UTF-8 LANG=C.UTF-8
fi

# MSYS's `ln -s` silently falls back to copying instead of erroring when it
# can't get symlink privilege — so without this, the "symlinks" below would
# quietly become disconnected copies that never see dotfiles-source edits.
# nativestrict forces a real Windows symlink or a hard failure, no silent copy.
if is_windows; then
	export MSYS=winsymlinks:nativestrict
fi

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# macOS: install the Homebrew package set first (the pacman-list analog). This
# also provides `stow` itself, so it must run before the stow check below. On
# Linux, packages come from pacman (see README) — brew is absent and skipped.
if is_macos && command -v brew &>/dev/null; then
	echo "Installing Homebrew packages (brew bundle)..."
	brew bundle --file="$DOTFILES/Brewfile" || \
		echo "  brew bundle reported errors — continuing (rerun it manually if needed)."
elif is_debian; then
	# TUXEDO OS / Ubuntu: provision the niri stack (apt + PPAs + scripts/cargo).
	# This also installs `stow`, so it must run before the stow check below.
	# On Arch/CachyOS packages are installed manually (see README) — no auto step.
	echo "Provisioning Debian/Ubuntu packages (debian/provision.sh)..."
	"$DOTFILES/debian/provision.sh" || \
		echo "  provisioning reported warnings — continuing (review them, rerun if needed)."
elif is_windows; then
	if command -v winget &>/dev/null; then
		echo "Installing GitHub CLI (winget)..."
		# command -v can miss a just-installed gh in a shell whose PATH was
		# cached before install (winget updates the registry, not this
		# process's env) — also check the well-known install path so a stale
		# PATH doesn't make winget re-run and print a misleading "error" for
		# what's actually just "no upgrade available".
		if ! command -v gh &>/dev/null && [[ ! -x "/c/Program Files/GitHub CLI/gh.exe" ]]; then
			winget install --id GitHub.cli -e --accept-package-agreements --accept-source-agreements || \
				echo "  winget install of gh reported errors — continuing (rerun manually if needed)."
		else
			echo "  gh already installed."
		fi
	else
		echo "  winget not found — install GitHub CLI manually: https://cli.github.com"
	fi
fi

# Windows has no stow (GNU stow isn't packaged for it, and most COMMON_DIRS
# packages target POSIX tools that don't apply here). The one thing every
# machine needs regardless of OS is the Claude Code skill set, so link that
# package directly and stop — no stow, no Linux/macOS-only steps below.
if is_windows; then
	echo "Linking Claude Code skills..."
	mkdir -p "$HOME/.claude/skills"
	shopt -s nullglob
	for skill_dir in "$DOTFILES"/claude-skills/.claude/skills/*/; do
		name="$(basename "$skill_dir")"
		target="$HOME/.claude/skills/$name"
		tmp="$target.new.$$"
		# `ln -sfn` can't atomically overwrite an existing directory symlink on
		# Windows (MSYS's replace-in-place hits a Windows rename restriction and
		# leaves a randomly-named stray link instead). Link at a temp name first
		# — under `set -e` a failure here leaves the existing link untouched
		# instead of deleting it before we know the replacement will work.
		rm -f "$tmp"
		ln -s "${skill_dir%/}" "$tmp"
		rm -rf "$target"
		mv "$tmp" "$target"
		echo "  linked $name"
	done
	shopt -u nullglob
	# claude/apply.sh is skipped here: its Python helper imports fcntl, which
	# doesn't exist on native Windows Python, so it hard-crashes on this OS.
	echo "Dotfiles installed successfully! (Windows: skills + gh only — see COMMON_DIRS in this script for what else exists)"
	exit 0
fi

# Codex CLI — official standalone installer for macOS/Linux. Keep normal
# dotfiles runs fast by installing only when absent; opt into an update with
# DOTFILES_UPDATE_CODEX=1. Authentication remains interactive on first launch.
if ! command -v codex >/dev/null 2>&1 || [[ "${DOTFILES_UPDATE_CODEX:-0}" == 1 ]]; then
	if command -v curl >/dev/null 2>&1; then
		echo "Installing/updating OpenAI Codex CLI..."
		if curl -fsSL https://chatgpt.com/codex/install.sh | sh; then
			export PATH="$HOME/.local/bin:$PATH"
		else
			echo "  Codex CLI install failed — continuing; rerun the official installer later." >&2
		fi
	else
		echo "  curl missing — skipping Codex CLI install." >&2
	fi
else
	echo "Codex CLI already installed: $(codex --version)"
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
# (niri, kanshi), the niri-session-anchor systemd user unit, and the bin/
# helper script (niri-screenshot, Linux-only). The Zen user.js is NOT stowed:
# ~/.config/zen is Zen's live profile root, so stowing into it would tree-fold
# the whole profile into the repo. link_browser_userjs symlinks the repo's
# user.js straight into the active profile instead.
COMMON_DIRS=(
	claude-skills
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

# Codex config, global guidance, docs MCP, and plugin — reconciled rather than
# stowed because ~/.codex also contains live auth, sessions, and project trust.
"$DOTFILES/codex/apply.sh"

# Claude Code compatibility — retained while Codex is the primary managed
# agent. ~/.claude.json is live-mutated by Claude itself.
"$DOTFILES/claude/apply.sh"

# Noctalia colorscheme — patched rather than stowed since Noctalia live-mutates
# its settings.json. Pins the Gruvbox scheme; Linux-only (no-op on macOS).
"$DOTFILES/noctalia/apply.sh"

# Zen Browser user.js — Zen's profile dir is per-install-hashed. Resolve the
# active profile from installs.ini/profiles.ini and symlink the repo's user.js
# into <profile>/user.js. Runs on both platforms; only the base dir differs.
# Idempotent — safe to rerun.
link_browser_userjs() {
	local zen_base zen_src zen_ini zen_prof
	# Read straight from the repo (not stowed) on both OSes — see COMMON_DIRS note.
	zen_src="$DOTFILES/zen/.config/zen/user.js"
	# Profile root differs: macOS App Support; Debian/tarball Zen uses ~/.zen
	# (Firefox-fork layout); Arch's zen-browser-bin uses ~/.config/zen.
	if is_macos; then
		zen_base="$HOME/Library/Application Support/zen/Profiles"
	elif is_debian; then
		zen_base="$HOME/.zen"
	else
		zen_base="$HOME/.config/zen"
	fi

	if [[ ! -e "$zen_src" ]]; then
		echo "  zen: no user.js source ($zen_src) — skipping."
		return
	fi
	if [[ ! -d "$zen_base" ]]; then
		echo "  zen: $zen_base missing — launch Zen once, then rerun."
		return
	fi

	# Resolve the active profile dir: installs.ini's Default= wins for the
	# running install; fall back to profiles.ini's first Default=1 profile.
	# The ini files live at the zen root (parent of Profiles/ on macOS).
	if is_macos; then zen_ini="$HOME/Library/Application Support/zen"
	elif is_debian; then zen_ini="$HOME/.zen"
	else zen_ini="$HOME/.config/zen"; fi
	zen_prof=""
	if [[ -f "$zen_ini/installs.ini" ]]; then
		zen_prof="$(awk -F= '/^Default=/{print $2; exit}' "$zen_ini/installs.ini")"
	fi
	if [[ -z "$zen_prof" && -f "$zen_ini/profiles.ini" ]]; then
		zen_prof="$(awk -F= '
			/^\[Profile/{p=""}
			/^Path=/{p=$2}
			/^Default=1/{if(p){print p; exit}}' "$zen_ini/profiles.ini")"
	fi
	if [[ -z "$zen_prof" ]]; then
		echo "  zen: no active profile in installs.ini/profiles.ini — launch Zen once, then rerun."
		return
	fi

	# Paths in the ini are relative to the zen root (e.g. "abcd.Default (release)").
	local zen_dir="$zen_ini/$zen_prof"
	if [[ ! -d "$zen_dir" ]]; then
		echo "  zen: resolved profile '$zen_prof' but $zen_dir missing — skipping."
		return
	fi

	# Don't relink our own symlink onto itself; back up a real user.js first.
	if [[ -L "$zen_dir/user.js" ]]; then
		: # already a symlink (ours) — ln -sfn below refreshes it
	elif [[ -e "$zen_dir/user.js" ]]; then
		mv "$zen_dir/user.js" "$zen_dir/user.js.bak.$(date +%s)"
		echo "  zen: backed up existing user.js → user.js.bak.*"
	fi
	ln -sfn "$zen_src" "$zen_dir/user.js"
	echo "  zen: linked user.js → $zen_dir/user.js"
}
link_browser_userjs

# macOS-only deployment for paths stow can't express (they live outside
# ~/.config). Idempotent — safe to rerun.
if is_macos; then
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
