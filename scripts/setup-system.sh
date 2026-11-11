#!/usr/bin/env bash
# Optional locale, keyboard, login-shell, memory-pressure, and sudo preferences.
# Leave hardware drivers, display managers, and power policy with the installed OS.
set -euo pipefail
# shellcheck source=scripts/setup-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-common.sh"
if ! is_macos && ! is_ubuntu; then
	echo "System preferences support Ubuntu and macOS." >&2
	exit 1
fi
banner "Locale"
# Make sure en_US.UTF-8 is generated so perl, locale-aware libs, and Niri
# don't spam warnings.
if is_macos; then
	echo "  macOS ships en_US.UTF-8 prebuilt (no locale-gen) — skipping."
elif is_ubuntu; then
	# Ubuntu's locale-gen takes the locale as an argument; LANG lives in
	# /etc/default/locale (via update-locale), NOT /etc/locale.conf.
	if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
		echo "  already present — skipping."
	elif confirm "Generate en_US.UTF-8? (needs sudo) [Y/n]"; then
		sudo locale-gen en_US.UTF-8
		sudo update-locale LANG=en_US.UTF-8
		echo "  generated (update-locale set LANG)."
	fi
else
	echo "  already present — skipping."
fi


banner "Caps Lock remap"
if is_macos; then
	# macOS has no keyd. Install a LaunchAgent that runs hidutil at login to
	# remap Caps Lock (0x700000039) → Left Command (0x7000000E3). Cmd is the
	# primary shortcut modifier on macOS, so caps→Cmd mirrors the caps→Ctrl
	# ergonomics used on Linux. A hidutil mapping is lost on reboot, so
	# RunAtLoad reapplies it every login.
	CAPS_PLIST="$HOME/Library/LaunchAgents/com.dotfiles.capstocommand.plist"
	CAPS_MAP='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E3}]}'
	if [[ -f "$CAPS_PLIST" ]]; then
		echo "  Caps→Cmd LaunchAgent already installed."
	elif confirm "Install Caps Lock → Command (hidutil LaunchAgent)? [Y/n]"; then
		mkdir -p "$HOME/Library/LaunchAgents"
		cat > "$CAPS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.dotfiles.capstocommand</string>
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
		echo "  installed Caps→Cmd LaunchAgent + applied for this session."
	fi
elif command -v keyd &>/dev/null || command -v keyd.rvaiya &>/dev/null; then
	# NOTE: the keyd-team Ubuntu PPA ships the binary as `keyd.rvaiya` (not
	# `keyd`) to dodge a name clash — while the systemd unit stays `keyd`. A
	# bare `command -v keyd` gate is exactly what silently skipped this whole
	# step on Ubuntu, leaving Caps Lock unmapped. So detect either name and
	# always reload through the (stable) service rather than the binary.
	KEYD_CONFIG=/etc/keyd/default.conf
	if [[ -f "$KEYD_CONFIG" ]] && grep -Eq '^[[:space:]]*capslock[[:space:]]*=[[:space:]]*leftcontrol' "$KEYD_CONFIG"; then
		echo "  remap already applied."
		sudo systemctl enable --now keyd 2>/dev/null || true
	elif [[ -f "$KEYD_CONFIG" ]]; then
		echo "  $KEYD_CONFIG exists with other rules — leaving alone."
		echo "  add 'capslock = leftcontrol' under [main] manually."
	elif confirm "Install keyd config? (needs sudo) [Y/n]"; then
		sudo install -d -m 755 /etc/keyd
		sudo tee "$KEYD_CONFIG" >/dev/null <<'CONF'
[ids]
*

[main]
capslock = leftcontrol
CONF
		sudo systemctl enable --now keyd
		sudo systemctl restart keyd   # re-read the config if keyd was already running
		echo "  remap applied + keyd (re)started."
	fi
else
	echo "  keyd not installed — skipping."
	echo "  ubuntu/provision.sh installs keyd from ppa:keyd-team/ppa."
fi


banner "Login shell"
if ! is_macos; then
CURRENT_USER="$(id -un)"
# `|| true`: under set -e a getpwnam miss (NSS/LDAP-only or odd container user)
# would otherwise abort the whole script here.
CURRENT_SHELL="$(getent passwd "$CURRENT_USER" | cut -d: -f7 || true)"

# chsh prompts for the current user's password and takes effect at next login.
ZSH_BIN="$(command -v zsh || true)"
# Compare by basename: passwd stores /bin/zsh but `command -v` yields
# /usr/bin/zsh (the usrmerge symlink), so a full-path equality test would never
# match and we'd re-prompt chsh on every run.
if [[ -z "$ZSH_BIN" ]]; then
	echo "  zsh not installed — skipping chsh (install zsh, then rerun)."
elif [[ "${CURRENT_SHELL##*/}" == zsh ]]; then
	echo "  login shell already zsh ($CURRENT_SHELL)."
elif confirm "Set login shell to zsh ($ZSH_BIN)? (prompts for your password) [Y/n]"; then
	# chsh refuses a shell that isn't listed in /etc/shells.
	grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null || echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
	if chsh -s "$ZSH_BIN"; then
		echo "  login shell set to $ZSH_BIN (applies at next login)."
	else
		echo "  chsh FAILED — set it by hand: chsh -s \"$ZSH_BIN\"" >&2
	fi
fi

fi

banner "Memory pressure"
if is_macos; then
	echo "  no systemd-oomd on macOS (jetsam/memorystatus handles pressure) — skipping."
else
OOMD_DROPIN_DIR=/etc/systemd/system/user@.service.d
OOMD_DROPIN_FILE="$OOMD_DROPIN_DIR/10-oomd.conf"
OOMD_UNIT=/usr/lib/systemd/system/systemd-oomd.service

if [[ ! -f "$OOMD_UNIT" ]]; then
	echo "  systemd-oomd.service not installed — skipping. Install systemd-oomd."
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
banner "sudo password feedback (show '*' while typing)"
# ---------------------------------------------------------------------------
# Ubuntu sudo is silent while typing the password; pwfeedback echoes '*'
# per char. Validated with visudo before it can take effect so a typo can't lock
# you out. (Safe on modern sudo — the old pwfeedback CVE was fixed in 1.8.31.)
if is_macos; then
	echo "  macOS sudo — pwfeedback drop-in is Linux-only, skipping."
else
	PWF=/etc/sudoers.d/pwfeedback
	if sudo test -f "$PWF" 2>/dev/null; then
		echo "  sudo pwfeedback already enabled."
	elif confirm "Show '*' while typing the sudo password? (needs sudo) [Y/n]"; then
		sudo install -m 0440 -o root -g root "$DOTFILES/sudoers.d/pwfeedback" "$PWF"
		if sudo visudo -c >/dev/null 2>&1; then
			echo "  enabled — sudo will echo '*' for the password."
		else
			sudo rm -f "$PWF"
			echo "  sudoers validation FAILED — reverted (no change)." >&2
		fi
	fi
fi


echo "System preferences complete. Log in again for login-shell changes."
