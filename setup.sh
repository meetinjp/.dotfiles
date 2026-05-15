#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# .dotfiles setup — run after install.sh
#
# What this does (in order):
#   1. Asks for git identity (or reads it from env vars).
#   2. Renders ~/.gitconfig (+ optional ~/.gitconfig-work) from templates.
#   3. Generates the en_US.UTF-8 locale on hosts that lack it.
#   4. Generates (or detects) an Ed25519 GPG key with sign + auth subkeys.
#   5. Configures gpg-agent to serve the auth subkey as an ssh-agent.
#   6. Installs a Caps Lock -> Ctrl remap via keyd.
#   7. Prints the public keys + a checklist of what to do next.
#
# Idempotent — safe to rerun. Each step short-circuits if its target
# already exists.
# ---------------------------------------------------------------------------

if ! command -v git &>/dev/null; then
	echo "Git is not installed. Please install it first."
	exit 1
fi

# confirm "prompt [Y/n]"
# - In a TTY: prompts the user.
# - Non-interactive (no TTY): skips unless DOTFILES_YES=1.
confirm() {
	local prompt="$1" default="${2:-y}" ans
	if [[ "${DOTFILES_YES:-0}" == "1" ]]; then
		[[ "$default" == "y" ]]
		return
	fi
	if [[ ! -t 0 ]]; then
		echo "  $prompt — no TTY, skipping (set DOTFILES_YES=1 to auto-accept)"
		return 1
	fi
	read -rp "  $prompt " ans
	ans="${ans:-$default}"
	[[ "$ans" =~ ^[yY] ]]
}

# prompt_var VAR_NAME "Label"
# Reads stdin if VAR_NAME isn't already exported.
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

banner() {
	echo
	echo "─── $1 ───────────────────────────────────────────────────────"
}

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GPG="$(command -v gpg || true)"
if [[ -z "$GPG" ]]; then
	echo "gpg not found. Install GnuPG and rerun."
	exit 1
fi
export GPG_TTY="$(tty 2>/dev/null || echo /dev/tty)"

echo "═════════════════════════════════════════════════════════════════"
echo " .dotfiles setup"
echo "═════════════════════════════════════════════════════════════════"

# ---------------------------------------------------------------------------
banner "1/6  Identity"
# ---------------------------------------------------------------------------
echo "Set via env vars to skip prompts: GIT_NAME, GIT_EMAIL, GIT_WORK_EMAIL, WSL_USER."
prompt_var GIT_NAME       "git name    (e.g. meetinjp)"
prompt_var GIT_EMAIL      "git personal email"
prompt_var GIT_WORK_EMAIL "git work email  (leave blank to skip)"

# WSL_USER goes into /etc/wsl.conf's `default=` line. Default to the
# current Linux user when running on WSL; the env var overrides.
ON_WSL=0
if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
	ON_WSL=1
	WSL_USER="${WSL_USER:-$(whoami)}"
	echo "  wsl user:   $WSL_USER"
fi

# ---------------------------------------------------------------------------
banner "2/6  Render config templates"
# ---------------------------------------------------------------------------
render_template() {
	local src="$1" dst="$2"
	sed -e "s|\${GIT_NAME}|${GIT_NAME}|g" \
	    -e "s|\${GIT_EMAIL}|${GIT_EMAIL}|g" \
	    -e "s|\${GIT_WORK_EMAIL}|${GIT_WORK_EMAIL:-}|g" \
	    -e "s|\${WSL_USER}|${WSL_USER:-}|g" \
	    "$src" > "$dst"
	echo "  wrote $dst"
}
render_template "$DOTFILES/git/gitconfig.template" ~/.gitconfig
if [[ -n "${GIT_WORK_EMAIL:-}" ]]; then
	render_template "$DOTFILES/git/gitconfig-work.template" ~/.gitconfig-work
else
	echo "  GIT_WORK_EMAIL empty — skipping ~/.gitconfig-work"
fi
if (( ON_WSL )); then
	render_template "$DOTFILES/wsl/etc/wsl.conf.template" "$DOTFILES/wsl/etc/wsl.conf"
	echo "  copy into /etc with:  sudo cp $DOTFILES/wsl/etc/wsl.conf /etc/wsl.conf"
else
	echo "  not on WSL — skipping wsl.conf render"
fi

# ---------------------------------------------------------------------------
banner "3/6  Locale (en_US.UTF-8)"
# ---------------------------------------------------------------------------
# Fresh Arch / WSL Arch ships with no generated locales, which makes perl
# (and anything else that consults LANG) spam warnings.
if command -v locale-gen &>/dev/null && ! locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
	if confirm "Generate en_US.UTF-8? (needs sudo) [Y/n]"; then
		if ! grep -q '^en_US\.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null; then
			echo 'en_US.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen >/dev/null
		fi
		sudo locale-gen
		if [[ ! -f /etc/locale.conf ]]; then
			echo 'LANG=en_US.UTF-8' | sudo tee /etc/locale.conf >/dev/null
		fi
		echo "  generated."
	fi
else
	echo "  already present — skipping."
fi

# ---------------------------------------------------------------------------
banner "4/6  GPG key (sign + auth, used for both git signing and SSH)"
# ---------------------------------------------------------------------------
# We use one GPG key for everything:
#   - primary [C] (certify) + [S] subkey: commit/tag signatures
#   - [A] subkey: SSH auth, served by gpg-agent's ssh-agent socket
if "$GPG" --list-secret-keys "$GIT_EMAIL" &>/dev/null; then
	KEYID="$("$GPG" --list-secret-keys --with-colons "$GIT_EMAIL" | awk -F: '/^sec:/ {print $5; exit}')"
	echo "  existing key for $GIT_EMAIL (keyid=$KEYID) — using it."
else
	if confirm "No key for $GIT_EMAIL. Generate Ed25519, 2y validity? [Y/n]"; then
		"$GPG" --quick-gen-key "$GIT_NAME <$GIT_EMAIL>" ed25519 default 2y
		KEYID="$("$GPG" --list-secret-keys --with-colons "$GIT_EMAIL" | awk -F: '/^sec:/ {print $5; exit}')"
		[[ -n "${GIT_WORK_EMAIL:-}" ]] && \
			"$GPG" --quick-add-uid "$KEYID" "$GIT_NAME <$GIT_WORK_EMAIL>"
		echo "  generated keyid=$KEYID."
	fi
fi

if [[ -n "${KEYID:-}" ]]; then
	git config --global user.signingkey "$KEYID"
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
banner "5/6  SSH-over-GPG (gpg-agent serves the auth subkey)"
# ---------------------------------------------------------------------------
AUTH_KEYGRIP=""
if [[ -n "${KEYID:-}" ]]; then
	mkdir -p ~/.gnupg && chmod 700 ~/.gnupg
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

# ---------------------------------------------------------------------------
banner "6/6  Caps Lock -> Ctrl (via keyd; Linux only)"
# ---------------------------------------------------------------------------
if command -v keyd &>/dev/null; then
	KEYD_CONFIG=/etc/keyd/default.conf
	if [[ -f "$KEYD_CONFIG" ]]; then
		if grep -Eq '^[[:space:]]*capslock[[:space:]]*=[[:space:]]*leftcontrol' "$KEYD_CONFIG"; then
			echo "  remap already applied."
		else
			echo "  $KEYD_CONFIG exists with other rules — leaving alone."
			echo "  add 'capslock = leftcontrol' under [main] manually."
		fi
	else
		if confirm "Install keyd config? (needs sudo) [Y/n]"; then
			sudo tee "$KEYD_CONFIG" >/dev/null <<'CONF'
[ids]
*

[main]
capslock = leftcontrol
CONF
			sudo systemctl enable --now keyd
			echo "  remap applied + keyd enabled."
		fi
	fi
else
	echo "  keyd not installed — skipping (Linux only; not relevant for WSL)."
fi

# ---------------------------------------------------------------------------
echo
echo "═════════════════════════════════════════════════════════════════"
echo " Done. Now do the following:"
echo "═════════════════════════════════════════════════════════════════"

STEP=1
if [[ -n "${KEYID:-}" ]]; then
	echo
	echo "$STEP. Open https://github.com/settings/gpg/new and paste:"
	echo "──────────────────────── BEGIN GPG ────────────────────────"
	"$GPG" --armor --export "$KEYID"
	echo "───────────────────────── END GPG ─────────────────────────"
	STEP=$((STEP + 1))

	if [[ -n "$AUTH_KEYGRIP" ]]; then
		echo
		echo "$STEP. Open https://github.com/settings/ssh/new and paste:"
		echo "──────────────────────── BEGIN SSH ────────────────────────"
		"$GPG" --export-ssh-key "$GIT_EMAIL"
		echo "───────────────────────── END SSH ─────────────────────────"
		STEP=$((STEP + 1))
	fi
fi

echo
echo "$STEP. Reload your shell so the new zshrc + gpg-agent socket take effect:"
echo "   exec zsh"
STEP=$((STEP + 1))

echo
echo "$STEP. Verify SSH-over-GPG can talk to GitHub (after the keys are added):"
echo "   ssh -T git@github.com"
STEP=$((STEP + 1))

echo
echo "$STEP. If the starship prompt is missing glyphs, install FiraCode Nerd Font"
echo "   on your terminal host (Windows side for WSL):"
echo "   https://github.com/ryanoasis/nerd-fonts/releases/latest"

echo
