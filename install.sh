#!/usr/bin/env bash
# Link selected configuration packages. Provisioning and integrations are explicit.
set -euo pipefail
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$DOTFILES/scripts/link.py" "$@"
