#!/usr/bin/env bash
set -euo pipefail

if ! command -v git &>/dev/null; then
	echo "Git is not installed. Please install it first."
	exit 1
fi

# confirm "prompt [Y/n]"
# - In a TTY: prompt the user.
# - Non-interactive (e.g. `bash setup.sh < /dev/null`): skip unless DOTFILES_YES=1.
# Each gated action is opt-in by default, so silent skip is the safe outcome.
confirm() {
	local prompt="$1" default="${2:-y}" ans
	if [[ "${DOTFILES_YES:-0}" == "1" ]]; then
		[[ "$default" == "y" ]]
		return
	fi
	if [[ ! -t 0 ]]; then
		echo "$prompt — no TTY, skipping (set DOTFILES_YES=1 to auto-accept)"
		return 1
	fi
	read -rp "$prompt " ans
	ans="${ans:-$default}"
	[[ "$ans" =~ ^[yY] ]]
}

# prompt_var VAR_NAME "Label"
# Reads stdin if VAR_NAME isn't already set in the env; respects DOTFILES_YES
# (which means "fail if missing" since we can't invent identity for you).
prompt_var() {
	local var="$1" label="$2" value
	value="${!var-}"
	if [[ -n "$value" ]]; then
		echo "  $label: $value"
		return
	fi
	if [[ ! -t 0 ]]; then
		echo "error: $var not set and no TTY to prompt. Pass it as an env var." >&2
		exit 1
	fi
	read -rp "  $label: " value
	printf -v "$var" '%s' "$value"
	export "${var?}"
}

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GPG="$(command -v gpg || true)"
if [[ -z "$GPG" ]]; then
	echo "gpg not found. Install GnuPG and rerun."
	exit 1
fi
export GPG_TTY="$(tty 2>/dev/null || echo /dev/tty)"

# --- Identity (renders gitconfig templates) ---
echo "Git identity (set via env vars to skip prompts):"
prompt_var GIT_NAME       "name        (e.g. meetinjp)"
prompt_var GIT_EMAIL      "personal email"
prompt_var GIT_WORK_EMAIL "work email (or leave blank to skip work config)"
echo

echo "Rendering git config templates..."
render_template() {
	local src="$1" dst="$2"
	# sed with | delimiter so emails with slashes (unlikely) don't blow up.
	sed -e "s|\${GIT_NAME}|${GIT_NAME}|g" \
	    -e "s|\${GIT_EMAIL}|${GIT_EMAIL}|g" \
	    -e "s|\${GIT_WORK_EMAIL}|${GIT_WORK_EMAIL}|g" \
	    "$src" > "$dst"
}
render_template "$DOTFILES/git/gitconfig.template" ~/.gitconfig
if [[ -n "${GIT_WORK_EMAIL:-}" ]]; then
	render_template "$DOTFILES/git/gitconfig-work.template" ~/.gitconfig-work
fi

# --- Locale (en_US.UTF-8) ---
# Fresh Arch / WSL Arch ships with no generated locales, which makes perl
# (and anything else that consults LANG) spam warnings. Generate the
# en_US.UTF-8 locale so future shells don't need the LC_ALL workaround.
if command -v locale-gen &>/dev/null && ! locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
	if confirm "Generate en_US.UTF-8 locale? (needs sudo) [Y/n]"; then
		if ! grep -q '^en_US\.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null; then
			echo 'en_US.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen >/dev/null
		fi
		sudo locale-gen
		if [[ ! -f /etc/locale.conf ]]; then
			echo 'LANG=en_US.UTF-8' | sudo tee /etc/locale.conf >/dev/null
		fi
		echo "Locale en_US.UTF-8 generated."
	fi
fi

# --- GPG key (signing + auth, used for both git signing and SSH) ---
# We use one GPG key for everything:
#   - primary [C] (certify) + [S] subkey: commit/tag signatures
#   - [A] subkey: SSH auth, served by gpg-agent through its ssh-agent socket
# This replaces a separate ~/.ssh/id_ed25519 — there's only one private key
# to back up, and `gpg --export-ssh-key` produces the public key in SSH
# format for github.com/settings/ssh/new.
if "$GPG" --list-secret-keys "$GIT_EMAIL" &>/dev/null; then
	KEYID="$("$GPG" --list-secret-keys --with-colons "$GIT_EMAIL" | awk -F: '/^sec:/ {print $5; exit}')"
	echo "GPG key for $GIT_EMAIL already exists (keyid=$KEYID) — using it."
else
	if confirm "Generate Ed25519 GPG signing key (2y, with both email UIDs)? [Y/n]"; then
		"$GPG" --quick-gen-key "$GIT_NAME <$GIT_EMAIL>" ed25519 default 2y
		KEYID="$("$GPG" --list-secret-keys --with-colons "$GIT_EMAIL" | awk -F: '/^sec:/ {print $5; exit}')"
		[[ -n "${GIT_WORK_EMAIL:-}" ]] && \
			"$GPG" --quick-add-uid "$KEYID" "$GIT_NAME <$GIT_WORK_EMAIL>"
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

	# --- Add [A]uthentication subkey for SSH-over-GPG ---
	if ! "$GPG" --list-keys --with-colons "$KEYID" | awk -F: '$1=="sub" && $12 ~ /a/{found=1} END{exit !found}'; then
		if confirm "Add SSH-over-GPG auth subkey to $KEYID? [Y/n]"; then
			"$GPG" --quick-add-key "$KEYID" ed25519 auth 2y
		fi
	fi

	# --- Configure gpg-agent to expose an SSH socket ---
	mkdir -p ~/.gnupg && chmod 700 ~/.gnupg
	if ! grep -q '^enable-ssh-support' ~/.gnupg/gpg-agent.conf 2>/dev/null; then
		echo 'enable-ssh-support' >> ~/.gnupg/gpg-agent.conf
	fi

	# Register the [A] subkey's keygrip with gpg-agent's sshcontrol so
	# the agent offers it over the ssh socket.
	AUTH_KEYGRIP="$("$GPG" --list-keys --with-colons --with-keygrip "$KEYID" | awk -F: '
		/^sub:/ { cap=$12; next }
		/^grp:/ { if (cap ~ /a/) { print $10; exit } }
	')"
	if [[ -n "$AUTH_KEYGRIP" ]]; then
		touch ~/.gnupg/sshcontrol
		if ! grep -q "^$AUTH_KEYGRIP" ~/.gnupg/sshcontrol; then
			echo "$AUTH_KEYGRIP" >> ~/.gnupg/sshcontrol
			echo "Registered SSH-over-GPG keygrip $AUTH_KEYGRIP."
		fi

		# Reload gpg-agent so the new socket / sshcontrol take effect.
		gpgconf --kill gpg-agent 2>/dev/null || true

		echo
		echo "Add the following at https://github.com/settings/ssh/new"
		echo "(this is the GPG auth subkey rendered in SSH pubkey format):"
		echo "------------------------------------------------------------"
		"$GPG" --export-ssh-key "$GIT_EMAIL"
		echo "------------------------------------------------------------"
		echo
	else
		echo "Note: no [A] subkey present — skipping SSH-over-GPG export."
	fi
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
		if confirm "Install keyd config for Caps Lock -> Ctrl? (needs sudo) [Y/n]"; then
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
