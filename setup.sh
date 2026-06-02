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
#   7. Disables any existing display manager + installs a getty@tty1
#      autologin drop-in. zsh's .zprofile takes over and execs niri-session.
#   8. Enables systemd-oomd with a user@.service drop-in so runaway
#      multi-agent workloads get surgically killed before swap death-spiral.
#   9. Prints the public keys + a checklist of what to do next.
#
# Apps deliberately NOT touched here: music player (install/pick at will,
# not part of the dotfile contract), browsers beyond firefox-developer-edition,
# any GUI app whose state lives entirely in its own settings UI.
#
# Idempotent — safe to rerun. Each step short-circuits if its target
# already exists.
# ---------------------------------------------------------------------------

is_macos() { [[ "$(uname -s)" == Darwin ]]; }

# Monotonic-ish timestamp for backup filenames. GNU date supports %N
# (nanoseconds); BSD/macOS date does not and echoes a literal "N", so detect
# that and fall back to whole seconds (the PID suffix still disambiguates).
_ts() {
	local t
	t="$(date +%s%N 2>/dev/null)"
	[[ -z "$t" || "$t" == *N* ]] && t="$(date +%s)"
	printf '%s' "$t"
}

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

# Hoisted once: ~/.gnupg has to exist with 700 before either the pinentry
# config (step 4) or the ssh-control file (step 5) gets touched.
mkdir -p ~/.gnupg && chmod 700 ~/.gnupg

# Reusable: extract primary key fingerprint from a UID.
gpg_keyid_for() {
	"$GPG" --list-secret-keys --with-colons --fingerprint "$1" \
		| awk -F: '/^fpr:/ {print $10; exit}'
}

echo "═════════════════════════════════════════════════════════════════"
echo " .dotfiles setup ($(uname -s))"
echo "═════════════════════════════════════════════════════════════════"

# ---------------------------------------------------------------------------
banner "1/8  Identity"
# ---------------------------------------------------------------------------
echo "Set via env vars to skip prompts: GIT_NAME, GIT_EMAIL, GIT_WORK_EMAIL."
prompt_var GIT_NAME       "git name    (e.g. meetinjp)"
prompt_var GIT_EMAIL      "git personal email"
prompt_var GIT_WORK_EMAIL "git work email  (leave blank to skip)"

# ---------------------------------------------------------------------------
banner "2/8  Render config templates"
# ---------------------------------------------------------------------------
render_template() {
	local src="$1" dst="$2"
	if [[ -f "$dst" ]]; then
		# nanosecond precision + PID so rapid back-to-back renders never collide.
		local bak="$dst.bak.$(_ts).$$"
		cp -p "$dst" "$bak"
		echo "  backed up existing $dst → $bak"
	fi
	sed -e "s|\${GIT_NAME}|${GIT_NAME}|g" \
	    -e "s|\${GIT_EMAIL}|${GIT_EMAIL}|g" \
	    -e "s|\${GIT_WORK_EMAIL}|${GIT_WORK_EMAIL:-}|g" \
	    "$src" > "$dst"
	echo "  wrote $dst"
}
render_template "$DOTFILES/git/gitconfig.template" ~/.gitconfig
if [[ -n "${GIT_WORK_EMAIL:-}" ]]; then
	render_template "$DOTFILES/git/gitconfig-work.template" ~/.gitconfig-work
else
	echo "  GIT_WORK_EMAIL empty — skipping ~/.gitconfig-work"
fi

# ---------------------------------------------------------------------------
banner "3/8  Locale (en_US.UTF-8)"
# ---------------------------------------------------------------------------
# Make sure en_US.UTF-8 is generated so perl, locale-aware libs, and Niri
# don't spam warnings.
if is_macos; then
	echo "  macOS ships en_US.UTF-8 prebuilt (no locale-gen) — skipping."
elif command -v locale-gen &>/dev/null && ! locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
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
banner "4/8  GPG key (sign + auth, used for both git signing and SSH)"
# ---------------------------------------------------------------------------
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
banner "5/8  SSH-over-GPG (gpg-agent serves the auth subkey)"
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

# ---------------------------------------------------------------------------
banner "6/8  Caps Lock -> Ctrl (via keyd)"
# ---------------------------------------------------------------------------
if is_macos; then
	# macOS has no keyd. Install a LaunchAgent that runs hidutil at login to
	# remap Caps Lock (0x700000039) → Left Control (0x7000000E0). A hidutil
	# mapping is lost on reboot, so RunAtLoad reapplies it every login.
	CAPS_PLIST="$HOME/Library/LaunchAgents/com.dotfiles.capstocontrol.plist"
	CAPS_MAP='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}'
	if [[ -f "$CAPS_PLIST" ]]; then
		echo "  Caps→Ctrl LaunchAgent already installed."
	elif confirm "Install Caps Lock → Control (hidutil LaunchAgent)? [Y/n]"; then
		mkdir -p "$HOME/Library/LaunchAgents"
		cat > "$CAPS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.dotfiles.capstocontrol</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/hidutil</string>
		<string>property</string>
		<string>--set</string>
		<string>$CAPS_MAP</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST
		launchctl bootstrap "gui/$(id -u)" "$CAPS_PLIST" 2>/dev/null || true
		/usr/bin/hidutil property --set "$CAPS_MAP" >/dev/null 2>&1 || true
		echo "  installed Caps→Ctrl LaunchAgent + applied for this session."
	fi
elif command -v keyd &>/dev/null; then
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
			sudo install -d -m 755 /etc/keyd
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
	echo "  keyd not installed — skipping (install with: sudo pacman -S keyd)."
fi

# ---------------------------------------------------------------------------
banner "7/8  Autologin to tty1 (boots straight into zsh → niri-session)"
# ---------------------------------------------------------------------------
# No display manager: getty@tty1 autologins this user via a systemd drop-in.
# zsh's .zprofile (stowed) then execs niri-session when it sees tty1 + no
# live Wayland session. One fewer moving part than greetd; if niri crashes,
# you land on a zsh prompt at tty1 and can poke around.

if is_macos; then
	echo "  macOS uses loginwindow/WindowServer, not getty/niri — skipping."
	echo "  (Set autologin in System Settings > Users & Groups if you want it.)"
else
CURRENT_USER="$(id -un)"
OVERRIDE_DIR=/etc/systemd/system/getty@tty1.service.d
OVERRIDE_FILE="$OVERRIDE_DIR/autologin.conf"

# First, disable any display manager that's currently enabled (CachyOS ships
# sddm enabled by default; gdm on Fedora-likes; etc.). They own
# /etc/systemd/system/display-manager.service and would race with our
# tty1 autologin.
for dm in gdm sddm lightdm ly greetd; do
	if systemctl is-enabled --quiet "$dm.service" 2>/dev/null; then
		if confirm "Disable existing display manager $dm.service? [Y/n]"; then
			# --now also stops a running DM in case setup.sh is rerun
			# from inside a graphical session (which doesn't survive anyway
			# after the autologin override claims tty1).
			sudo systemctl disable --now "$dm.service"
			echo "  disabled + stopped $dm.service"
		fi
	fi
done

# Install the getty@tty1 autologin drop-in. Idempotent — skips if our override
# already references the current user. Match the full ExecStart token so
# usernames that are substrings of another don't false-match.
if sudo test -f "$OVERRIDE_FILE" && sudo grep -q "autologin $CURRENT_USER %I" "$OVERRIDE_FILE"; then
	echo "  $OVERRIDE_FILE already autologins $CURRENT_USER."
else
	if confirm "Write getty@tty1 autologin override for user $CURRENT_USER? (needs sudo) [Y/n]"; then
		sudo install -d -m 755 "$OVERRIDE_DIR"
		sudo tee "$OVERRIDE_FILE" >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $CURRENT_USER %I \$TERM
EOF
		sudo systemctl daemon-reload
		echo "  wrote $OVERRIDE_FILE (autologin user = $CURRENT_USER)"
	fi
fi
fi

# ---------------------------------------------------------------------------
banner "8/8  systemd-oomd (kill runaway agents before swap death-spiral)"
# ---------------------------------------------------------------------------
# Without oomd: one Claude/agent eats all RAM → kernel OOM-killer fires
# randomly, often kills the WM and tanks the session. With oomd: the
# specific cgroup is killed under memory pressure, rest of session lives.
if is_macos; then
	echo "  no systemd-oomd on macOS (jetsam/memorystatus handles pressure) — skipping."
else
OOMD_DROPIN_DIR=/etc/systemd/system/user@.service.d
OOMD_DROPIN_FILE="$OOMD_DROPIN_DIR/10-oomd.conf"
OOMD_UNIT=/usr/lib/systemd/system/systemd-oomd.service

if [[ ! -f "$OOMD_UNIT" ]]; then
	echo "  systemd-oomd.service not installed — skipping. Install systemd-oomd-defaults."
elif systemctl is-enabled --quiet systemd-oomd.service 2>/dev/null; then
	echo "  systemd-oomd.service already enabled."
else
	if confirm "Enable systemd-oomd.service? (needs sudo) [Y/n]"; then
		sudo systemctl enable --now systemd-oomd.service
		echo "  systemd-oomd enabled + started."
	fi
fi

# user@.service drop-in tells oomd to watch the user slice and kill the
# heaviest offending cgroup under memory pressure.
if sudo test -f "$OOMD_DROPIN_FILE"; then
	echo "  $OOMD_DROPIN_FILE already present."
else
	if confirm "Write user@.service oomd drop-in? (needs sudo) [Y/n]"; then
		sudo install -d -m 755 "$OOMD_DROPIN_DIR"
		sudo tee "$OOMD_DROPIN_FILE" >/dev/null <<'EOF'
[Service]
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=50%
EOF
		sudo systemctl daemon-reload
		echo "  wrote $OOMD_DROPIN_FILE"
	fi
fi
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
if is_macos; then
	echo "$STEP. zsh is already default on macOS (Catalina+); Apple's /bin/zsh is"
	echo "   fine. Homebrew's zsh is NOT in the Brewfile — install it BEFORE chsh,"
	echo "   else the login shell points at a missing binary and breaks on reboot"
	echo "   (recover with: chsh -s /bin/zsh):"
	echo "   brew install zsh && echo \"\$(brew --prefix)/bin/zsh\" | sudo tee -a /etc/shells && chsh -s \"\$(brew --prefix)/bin/zsh\""
else
	echo "$STEP. Switch your shell to zsh (CachyOS defaults to fish):"
	echo "   chsh -s /bin/zsh"
fi
STEP=$((STEP + 1))

echo
echo "$STEP. Verify SSH-over-GPG can talk to GitHub (after the keys are added):"
echo "   ssh -T git@github.com"
STEP=$((STEP + 1))

echo
if is_macos; then
	echo "$STEP. Restart to apply the Caps→Ctrl LaunchAgent + shell change:"
	echo "   sudo shutdown -r now      # or just log out / back in"
	STEP=$((STEP + 1))

	echo
	echo "$STEP. After login, sanity-check the stack:"
	echo "   ghostty --version                                   # terminal up"
	echo "   gpg --version && gpgconf --list-dirs agent-ssh-socket   # gpg-ssh"
	echo "   system_profiler SPDisplaysDataType | grep Chipset   # GPU"
	echo "   xcode-select -p                                     # Xcode toolchain path"
	STEP=$((STEP + 1))

	echo
	echo "$STEP. React Native / iOS build: install the FULL Xcode 26 app — on Intel"
	echo "   download the *Universal* .xip from developer.apple.com (the App Store"
	echo "   and the 'xcodes' CLI can ship an arm64-only build that won't launch)."
	echo "   Then per project: rbenv install \$(cat .ruby-version); bundle install;"
	echo "   bundle exec pod install. Full walkthrough: README 'React Native / iOS'."
else
	echo "$STEP. Reboot to land in niri (tty1 autologin → niri-session):"
	echo "   sudo systemctl reboot"
	STEP=$((STEP + 1))

	echo
	echo "$STEP. After login, sanity-check the stack:"
	echo "   niri msg version          # niri up"
	echo "   ghostty --version         # terminal up"
	echo "   prime-run glxinfo | grep 'OpenGL renderer'   # should say NVIDIA"
	echo "   glxinfo | grep 'OpenGL renderer'             # should say AMD (iGPU)"
fi

echo
