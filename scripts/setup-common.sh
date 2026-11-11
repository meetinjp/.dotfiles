#!/usr/bin/env bash
# Shared helpers for explicitly requested system and key setup tasks.
# shellcheck disable=SC2034 # DOTFILES is consumed by the sourcing scripts.
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
is_macos() { [[ "$(uname -s)" == Darwin ]]; }
is_ubuntu() {
	[[ "$(uname -s)" == Linux && -r /etc/os-release ]] || return 1
	local ID='' ID_LIKE=''
	# shellcheck disable=SC1091
	. /etc/os-release
	[[ "$ID" == ubuntu || " $ID_LIKE " == *" ubuntu "* ]]
}
confirm() {
	local prompt="$1" default="${2:-y}" answer
	if [[ "${DOTFILES_YES:-0}" == 1 ]]; then
		[[ "$default" == y ]]
		return
	fi
	if [[ ! -t 0 ]]; then
		echo "  $prompt — no TTY, skipping (set DOTFILES_YES=1 to accept)."
		return 1
	fi
	read -rp "  $prompt " answer
	[[ "${answer:-$default}" =~ ^[yY] ]]
}
banner() { printf '\n%s\n' "$1"; }
