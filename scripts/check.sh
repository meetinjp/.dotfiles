#!/usr/bin/env bash
# Fast local checks; no provisioning, authentication, or real cloud access.
set -euo pipefail
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTFILES"
for source in nvim/.config/nvim/init.lua agent-skills/caveman/skills/caveman/SKILL.md; do
	if [[ ! -f "$source" ]]; then
		echo "Missing check prerequisite: $source" >&2
		echo "Run: git submodule update --init --recursive" >&2
		exit 1
	fi
done
shell_files=()
while IFS= read -r -d '' file; do
	[[ -f "$file" ]] || continue
	case "$file" in
		*.sh|bin/.local/bin/niri-screenshot|bin/.local/bin/proton-sync)
			bash -n "$file"
			shell_files+=("$file")
			;;
	esac
done < <(git ls-files -z --cached --others --exclude-standard)
if command -v shellcheck >/dev/null 2>&1; then
	shellcheck --severity=warning -x "${shell_files[@]}"
else
	echo "ShellCheck unavailable; static shell checks skipped."
fi
if command -v zsh >/dev/null 2>&1; then
	zsh -n zsh/.zshrc zsh/.zprofile
else
	echo "zsh unavailable; zsh syntax checks skipped."
fi
if command -v niri >/dev/null 2>&1; then
	niri validate -c "$DOTFILES/niri/.config/niri/config.kdl"
else
	echo "niri unavailable; compositor validation skipped."
fi
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
git diff --check
git diff --cached --check
