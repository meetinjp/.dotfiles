#!/usr/bin/env bash
# Explicit GPG signing and SSH-agent setup. Private key material stays outside Git.
set -euo pipefail
# shellcheck source=scripts/setup-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-common.sh"
GIT_NAME="${GIT_NAME:-$(git config --global --includes user.name || true)}"
GIT_EMAIL="${GIT_EMAIL:-$(git config --global --includes user.email || true)}"
if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
	echo "Configure identity first with ./setup.sh git." >&2
	exit 1
fi
GPG="$(command -v gpg || true)"
[[ -n "$GPG" ]] || { echo "Install GnuPG before configuring keys." >&2; exit 1; }
GPG_TTY="$(tty 2>/dev/null || echo /dev/tty)"
export GPG_TTY
mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"
gpg_keyid_for() {
	"$GPG" --list-secret-keys --with-colons --fingerprint "$1" | awk -F: '/^fpr:/ {print $10; exit}'
}
# Stage gpg-agent BEFORE we try to use it. On a fresh box without a populated
# graphical session, /usr/bin/pinentry's dispatcher can hang silently when
# gpg-agent first asks for a passphrase — the dispatcher tries to pick a GUI
# variant and waits forever for a display that isn't there. pinentry-curses
# draws inline in the TTY and works regardless of session state, so we pin it
# up-front. Idempotent. (~/.gnupg already prepared at top of script.)
if ! grep -q '^pinentry-program' ~/.gnupg/gpg-agent.conf 2>/dev/null; then
	# Resolve the pinentry binary dynamically (honors the Homebrew prefix on
	# macOS — /opt/homebrew or /usr/local — instead of a hardcoded /usr/bin).
	# macOS prefers pinentry-mac (GUI, Keychain-aware); Linux uses
	# pinentry-curses, which draws inline in the TTY and works regardless of
	# graphical-session state (avoids the dispatcher hang on a fresh box).
	if is_macos; then
		PINENTRY="$(command -v pinentry-mac || command -v pinentry-curses || command -v pinentry || true)"
	else
		PINENTRY="$(command -v pinentry-curses || command -v pinentry || true)"
	fi
	if [[ -n "$PINENTRY" ]]; then
		echo "pinentry-program $PINENTRY" >> ~/.gnupg/gpg-agent.conf
		echo "  pinned pinentry-program = $PINENTRY"
		gpgconf --kill gpg-agent 2>/dev/null || true
	else
		echo "  no pinentry found — install pinentry-mac (macOS) / pinentry (Linux) and rerun."
	fi
else
	echo "  pinentry-program already set."
fi

# One GPG key for everything:
#   - primary [C] (certify) + [S] subkey: commit/tag signatures
#   - [A] subkey: SSH auth, served by gpg-agent's ssh-agent socket
if "$GPG" --list-secret-keys "$GIT_EMAIL" &>/dev/null; then
	KEYID="$(gpg_keyid_for "$GIT_EMAIL")"
	echo "  existing key for $GIT_EMAIL (keyid=$KEYID) — using it."
else
	if confirm "No key for $GIT_EMAIL. Generate Ed25519, 2y validity? [Y/n]"; then
		"$GPG" --quick-gen-key "$GIT_NAME <$GIT_EMAIL>" ed25519 default 2y
		KEYID="$(gpg_keyid_for "$GIT_EMAIL")"
		[[ -n "${GIT_WORK_EMAIL:-}" ]] && \
			"$GPG" --quick-add-uid "$KEYID" "$GIT_NAME <$GIT_WORK_EMAIL>"
		echo "  generated keyid=$KEYID."
	fi
fi

if [[ -n "${KEYID:-}" ]]; then
	git config --global user.signingkey "$KEYID"
	git config --global gpg.format openpgp
	git config --global commit.gpgsign true
	git config --global tag.gpgsign true
	git config --global gpg.program "$GPG"

	# Add [A] authentication subkey if missing.
	if ! "$GPG" --list-keys --with-colons "$KEYID" | awk -F: '$1=="sub" && $12 ~ /a/{found=1} END{exit !found}'; then
		if confirm "No [A] subkey on $KEYID. Add one (ed25519, 2y) for SSH-over-GPG? [Y/n]"; then
			"$GPG" --quick-add-key "$KEYID" ed25519 auth 2y
			echo "  added [A] subkey."
		fi
	else
		echo "  [A] subkey already present."
	fi
fi

# ---------------------------------------------------------------------------
banner "5/10  SSH-over-GPG (gpg-agent serves the auth subkey)"
# ---------------------------------------------------------------------------
AUTH_KEYGRIP=""
if [[ -n "${KEYID:-}" ]]; then
	# ~/.gnupg already exists with 700 perms (hoisted at top).
	if ! grep -q '^enable-ssh-support' ~/.gnupg/gpg-agent.conf 2>/dev/null; then
		echo 'enable-ssh-support' >> ~/.gnupg/gpg-agent.conf
		echo "  enabled ssh-support in ~/.gnupg/gpg-agent.conf"
	else
		echo "  ssh-support already enabled in ~/.gnupg/gpg-agent.conf"
	fi

	AUTH_KEYGRIP="$("$GPG" --list-keys --with-colons --with-keygrip "$KEYID" | awk -F: '
		/^sub:/ { cap=$12; next }
		/^grp:/ { if (cap ~ /a/) { print $10; exit } }
	')"
	if [[ -n "$AUTH_KEYGRIP" ]]; then
		touch ~/.gnupg/sshcontrol
		if ! grep -q "^$AUTH_KEYGRIP" ~/.gnupg/sshcontrol; then
			echo "$AUTH_KEYGRIP" >> ~/.gnupg/sshcontrol
			echo "  registered keygrip $AUTH_KEYGRIP in ~/.gnupg/sshcontrol"
		else
			echo "  keygrip $AUTH_KEYGRIP already in ~/.gnupg/sshcontrol"
		fi
		gpgconf --kill gpg-agent 2>/dev/null || true
		echo "  gpg-agent reloaded."
	else
		echo "  no [A] subkey present — SSH-over-GPG not configured."
	fi
fi


if [[ -n "${KEYID:-}" ]]; then
	echo "Register the public signing key at https://github.com/settings/gpg/new:"
	"$GPG" --armor --export "$KEYID"
	if [[ -n "$AUTH_KEYGRIP" ]]; then
		echo "Register the public SSH key at https://github.com/settings/ssh/new:"
		"$GPG" --export-ssh-key "$GIT_EMAIL"
	fi
fi
