#!/usr/bin/env bash
set -euo pipefail

if ! command -v git &>/dev/null; then
	echo "Git is not installed. Please install it first."
	exit 1
fi

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve gpg — PATH on Git Bash (Windows) doesn't include it by default.
GPG="$(command -v gpg || true)"
if [[ -z "$GPG" && -x "/c/Program Files/Git/usr/bin/gpg.exe" ]]; then
	GPG="/c/Program Files/Git/usr/bin/gpg.exe"
fi
if [[ -z "$GPG" ]]; then
	echo "gpg not found. Install GnuPG and rerun."
	exit 1
fi

echo "Installing git config templates..."
cp -f "$DOTFILES/git/.gitconfig"      ~/.gitconfig
cp -f "$DOTFILES/git/.gitconfig-work" ~/.gitconfig-work

PERSONAL_EMAIL="$(git config --file ~/.gitconfig user.email)"
WORK_EMAIL="$(git config --file ~/.gitconfig-work user.email)"

echo "  name:       $(git config --file ~/.gitconfig user.name)"
echo "  personal:   $PERSONAL_EMAIL"
echo "  work:       $WORK_EMAIL (auto on repos under ~/work/lunar/)"
echo

# --- SSH key ---
if [[ -f ~/.ssh/id_ed25519 ]]; then
	echo "SSH key already at ~/.ssh/id_ed25519 — skipping."
else
	read -rp "Generate Ed25519 SSH key? [Y/n] " ans
	if [[ ! "${ans:-y}" =~ ^[nN] ]]; then
		mkdir -p ~/.ssh && chmod 700 ~/.ssh
		ssh-keygen -t ed25519 -C "$PERSONAL_EMAIL" -f ~/.ssh/id_ed25519
		echo
		echo "Add this SSH public key at https://github.com/settings/ssh/new"
		echo "------------------------------------------------------------"
		cat ~/.ssh/id_ed25519.pub
		echo "------------------------------------------------------------"
		echo
	fi
fi

# --- GPG key ---
if "$GPG" --list-secret-keys "$PERSONAL_EMAIL" &>/dev/null; then
	KEYID="$("$GPG" --list-secret-keys --with-colons "$PERSONAL_EMAIL" | awk -F: '/^sec:/ {print $5; exit}')"
	echo "GPG key for $PERSONAL_EMAIL already exists (keyid=$KEYID) — using it."
else
	read -rp "Generate Ed25519 GPG signing key (2y, with both email UIDs)? [Y/n] " ans
	if [[ ! "${ans:-y}" =~ ^[nN] ]]; then
		"$GPG" --quick-gen-key "meetinjp <$PERSONAL_EMAIL>" ed25519 default 2y
		KEYID="$("$GPG" --list-secret-keys --with-colons "$PERSONAL_EMAIL" | awk -F: '/^sec:/ {print $5; exit}')"
		"$GPG" --quick-add-uid "$KEYID" "meetinjp <$WORK_EMAIL>"
		echo
		echo "Add this GPG public key at https://github.com/settings/gpg/new"
		echo "------------------------------------------------------------"
		"$GPG" --armor --export "$KEYID"
		echo "------------------------------------------------------------"
		echo
	fi
fi

if [[ -n "${KEYID:-}" ]]; then
	git config --global user.signingkey "$KEYID"
	git config --global gpg.program "$GPG"
fi

# --- Caps Lock -> Ctrl via keyd (Linux; no-op if keyd isn't installed) ---
if command -v keyd &>/dev/null; then
	KEYD_CONFIG=/etc/keyd/default.conf
	if [[ -f "$KEYD_CONFIG" ]]; then
		if grep -Eq '^[[:space:]]*capslock[[:space:]]*=[[:space:]]*leftcontrol' "$KEYD_CONFIG"; then
			echo "Caps Lock -> Ctrl remap (keyd): already applied."
		else
			echo "$KEYD_CONFIG exists with other rules — not overwriting. Add 'capslock = leftcontrol' under [main] manually."
		fi
	else
		read -rp "Install keyd config for Caps Lock -> Ctrl? (needs sudo) [Y/n] " ans
		if [[ ! "${ans:-y}" =~ ^[nN] ]]; then
			sudo tee "$KEYD_CONFIG" >/dev/null <<'CONF'
[ids]
*

[main]
capslock = leftcontrol
CONF
			sudo systemctl enable --now keyd
			echo "Caps Lock -> Ctrl remap (keyd): applied."
		fi
	fi
fi

echo "Setup complete."
