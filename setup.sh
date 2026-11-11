#!/usr/bin/env bash
# Run one explicit setup task; normal config installation does not call these.
set -euo pipefail
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:---help}" in
	git) shift; exec python3 "$DOTFILES/scripts/setup-git.py" "$@" ;;
	keys|system)
		task="$1"; shift
		[[ $# == 0 ]] || { echo "Unexpected argument: $1" >&2; exit 2; }
		exec bash "$DOTFILES/scripts/setup-$task.sh"
		;;
	--help|-h)
		printf '%s\n' 'Usage: ./setup.sh git|keys|system' \
			'  git     Configure identity without replacing unrelated Git settings.' \
			'  keys    Configure GPG signing and SSH-over-GPG explicitly.' \
			'  system  Optional locale, keyboard, shell, memory, and sudo preferences.'
		;;
	*) echo "Unknown setup task: $1" >&2; exit 2 ;;
esac
