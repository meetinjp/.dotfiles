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
#   6. Remaps Caps Lock: Ctrl on Linux (keyd), Cmd on macOS (hidutil).
#   7. TUXEDO hardware (Linux): installs tuxedo-drivers + tuxedo-rs (tailord)
#      for keyboard backlight / fan control, and a battery charge-limit unit.
#   8. Sets the login shell to zsh, disables any display manager, installs a
#      getty@tty1 autologin drop-in, and silences the CachyOS fish greeting.
#      zsh's .zprofile then execs niri --session on tty1.
#   9. Enables systemd-oomd with a user@.service drop-in so runaway
#      multi-agent workloads get surgically killed before swap death-spiral.
#  10. Enables sudo pwfeedback (shows '*' while typing the password).
#  11. Prints the public keys + a checklist of what to do next.
#
# Apps deliberately NOT touched here: music player (install/pick at will,
# not part of the dotfile contract), browsers beyond the default (Zen),
# any GUI app whose state lives entirely in its own settings UI.
#
# Idempotent — safe to rerun. Each step short-circuits if its target
# already exists.
# ---------------------------------------------------------------------------

is_macos()  { [[ "$(uname -s)" == Darwin ]]; }
# Distro family (Linux). CachyOS → ID_LIKE=arch; TUXEDO OS → ID=ubuntu/ID_LIKE=debian.
is_debian() { [[ "$(uname -s)" == Linux ]] && grep -qiE '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release 2>/dev/null; }
is_arch()   { [[ "$(uname -s)" == Linux ]] && grep -qiE '^(ID|ID_LIKE)=.*arch' /etc/os-release 2>/dev/null; }

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
banner "1/10  Identity"
# ---------------------------------------------------------------------------
echo "Set via env vars to skip prompts: GIT_NAME, GIT_EMAIL, GIT_WORK_EMAIL."
prompt_var GIT_NAME       "git name    (e.g. meetinjp)"
prompt_var GIT_EMAIL      "git personal email"
prompt_var GIT_WORK_EMAIL "git work email  (leave blank to skip)"

# ---------------------------------------------------------------------------
banner "2/10  Render config templates"
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
banner "3/10  Locale (en_US.UTF-8)"
# ---------------------------------------------------------------------------
# Make sure en_US.UTF-8 is generated so perl, locale-aware libs, and Niri
# don't spam warnings.
if is_macos; then
	echo "  macOS ships en_US.UTF-8 prebuilt (no locale-gen) — skipping."
elif is_debian; then
	# Ubuntu's locale-gen takes the locale as an argument; LANG lives in
	# /etc/default/locale (via update-locale), NOT /etc/locale.conf.
	if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
		echo "  already present — skipping."
	elif confirm "Generate en_US.UTF-8? (needs sudo) [Y/n]"; then
		sudo locale-gen en_US.UTF-8
		sudo update-locale LANG=en_US.UTF-8
		echo "  generated (update-locale set LANG)."
	fi
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
banner "4/10  GPG key (sign + auth, used for both git signing and SSH)"
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

# ---------------------------------------------------------------------------
banner "6/10  Caps Lock remap (Linux: Ctrl via keyd / macOS: Cmd via hidutil)"
# ---------------------------------------------------------------------------
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
	# step on Tuxedo OS, leaving Caps Lock unmapped. So detect either name and
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
	echo "  (Arch: sudo pacman -S keyd | Tuxedo OS: debian/provision.sh adds ppa:keyd-team/ppa)"
fi

# ---------------------------------------------------------------------------
banner "7/10  TUXEDO hardware (drivers + fan/charge control)"
# ---------------------------------------------------------------------------
# TUXEDO laptops need out-of-tree bits that Tuxedo OS preinstalls but a vanilla
# Arch/CachyOS box does not:
#   - tuxedo-drivers-dkms: kernel modules for the white keyboard backlight
#     (LED class white:kbd_backlight), fan/thermal control, the tuxedo_io
#     control interface, and the battery charge-limit sysfs. DKMS rebuilds
#     against every installed kernel's headers on each kernel update.
#   - tuxedo-rs (tailord daemon + tailor-gui GTK app): lightweight fan-curve /
#     profile control. Chosen over Tuxedo Control Center (Electron + tccd) — it
#     is native GTK4 and does NOT fight power-profiles-daemon over the CPU
#     governor. After the first install, REBOOT once so the platform modules
#     bind cleanly (tuxedo-drivers blacklists the in-tree uniwill_laptop module).
# Skipped on macOS and on non-TUXEDO hardware.
if is_macos; then
	echo "  macOS — no TUXEDO drivers. Skipping."
elif is_debian; then
	echo "  TUXEDO OS / Debian ships tuxedo-drivers + Tuxedo Control Center + the"
	echo "  TUXEDO kernel natively — skipping all manual hardware enablement."
elif [[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" != *TUXEDO* ]]; then
	echo "  not a TUXEDO machine (sys_vendor != TUXEDO) — skipping."
elif ! command -v paru &>/dev/null; then
	echo "  paru (AUR helper) not found — skipping. Install it, then rerun, or:"
	echo "    paru -S --needed tuxedo-drivers-dkms tailord tailor-gui"
else
	TUXEDO_PKGS=(tuxedo-drivers-dkms tailord tailor-gui)
	# Wired 2.5G Ethernet (Motorcomm YT6801) has an in-tree driver on recent
	# kernels but it is MISSING from linux-cachyos-lts — add the DKMS module so
	# Ethernet also works when booting the LTS fallback kernel.
	if pacman -Qq linux-cachyos-lts &>/dev/null \
	   && confirm "Also install tuxedo-yt6801-dkms-git? (wired 2.5G Ethernet on the LTS kernel) [Y/n]"; then
		TUXEDO_PKGS+=(tuxedo-yt6801-dkms-git)
	fi
	# Building tailor-gui compiles Rust. CachyOS ships `rustup` with NO default
	# toolchain, so `rustc` is a proxy that errors and meson aborts with
	# "Unknown compiler(s): [['rustc']]". Select a default if one isn't set.
	if command -v rustup &>/dev/null && ! rustup default &>/dev/null; then
		if confirm "rustup has no default toolchain (tailor-gui won't build) — set 'stable'? [Y/n]"; then
			rustup default stable
		fi
	fi
	if confirm "Install TUXEDO packages via paru: ${TUXEDO_PKGS[*]}? [Y/n]"; then
		paru -S --needed "${TUXEDO_PKGS[@]}"
	fi

	# tailord: fan/profile daemon. Enable so fan control is active at boot.
	if [[ -f /usr/lib/systemd/system/tailord.service ]] \
	   && ! systemctl is-enabled --quiet tailord.service 2>/dev/null; then
		if confirm "Enable tailord.service (fan-control daemon)? (needs sudo) [Y/n]"; then
			sudo systemctl enable --now tailord.service
			echo "  tailord enabled."
		fi
	fi

	# Predefined fan presets (quiet / balanced / performance) → /etc/tailord so
	# they show up in tailor_gui's profile list. Copies only our presets; never
	# touches the shipped default.json. Re-runnable (overwrites our own files).
	if [[ -d "$DOTFILES/tailord" ]] && command -v tailord &>/dev/null; then
		if confirm "Install fan presets (quiet/balanced/performance, balanced default)? (needs sudo) [Y/n]"; then
			sudo install -d -m 755 /etc/tailord/fan /etc/tailord/profiles
			sudo cp "$DOTFILES"/tailord/fan/*.json      /etc/tailord/fan/
			sudo cp "$DOTFILES"/tailord/profiles/*.json /etc/tailord/profiles/
			# Make 'balanced' the active/default profile (repoint BEFORE removing
			# default so active_profile.json never dangles), then drop tuxedo-rs's
			# shipped 'default' so only the three named levels show in tailor_gui.
			sudo ln -sfn profiles/balanced.json /etc/tailord/active_profile.json
			sudo rm -f /etc/tailord/profiles/default.json /etc/tailord/fan/default.json
			sudo systemctl try-restart tailord.service 2>/dev/null || true
			echo "  fan presets installed (active: balanced)."
		fi
	fi

	# Keyboard backlight OFF by default. The backlight (Fn+Space) has no
	# default-state module param, so a udev rule sets the LED to 0 when it
	# appears at boot, before login, so it never comes up lit.
	KBD_RULE=/etc/udev/rules.d/99-kbd-backlight-off.rules
	if sudo test -f "$KBD_RULE" 2>/dev/null; then
		echo "  kbd-backlight-off udev rule already present."
	elif confirm "Default the keyboard backlight to OFF at boot? (needs sudo) [Y/n]"; then
		sudo install -m 644 "$DOTFILES/udev/99-kbd-backlight-off.rules" "$KBD_RULE"
		sudo udevadm control --reload
		brightnessctl -d white:kbd_backlight set 0 >/dev/null 2>&1 || true
		echo "  keyboard backlight will default to off at boot."
	fi

	# Battery charge limit (longevity). The released tailord (0.2.5) can't set
	# this from its GUI yet, so persist it via a tiny systemd oneshot. TUXEDO
	# boards expose one of two knobs (both only after tuxedo-drivers loads):
	#   - numeric  .../charge_control_end_threshold        (write a percent, 80)
	#   - Uniwill  .../charging_profile/charging_profile    named profiles:
	#     high_capacity (100%) / balanced (~90%) / stationary (~80%)
	# The InfinityBook Pro 14 AMD Gen10 uses the profile knob. Detect whichever
	# exists; if neither (e.g. before the post-install reboot), hint and move on.
	CHARGE_PATH=""; CHARGE_VAL=""
	for c in /sys/class/power_supply/BAT0/charge_control_end_threshold \
	         /sys/class/power_supply/BAT1/charge_control_end_threshold; do
		[[ -w "$c" ]] && { CHARGE_PATH="$c"; CHARGE_VAL="80"; break; }
	done
	if [[ -z "$CHARGE_PATH" ]]; then
		CP=/sys/devices/platform/tuxedo_keyboard/charging_profile/charging_profile
		if [[ -w "$CP" ]] && grep -qw stationary "${CP%/*}/charging_profiles_available" 2>/dev/null; then
			CHARGE_PATH="$CP"; CHARGE_VAL="stationary"   # ~80% ceiling
		fi
	fi
	CHARGE_UNIT=/etc/systemd/system/battery-charge-limit.service
	if sudo test -f "$CHARGE_UNIT" 2>/dev/null; then
		echo "  battery-charge-limit.service already installed."
	elif [[ -z "$CHARGE_PATH" ]]; then
		echo "  charge-limit sysfs not present yet (tuxedo-drivers not loaded?)."
		echo "  REBOOT after the driver install, then rerun setup.sh to set the cap."
	elif confirm "Cap battery charge for longevity (set '$CHARGE_VAL')? (needs sudo) [Y/n]"; then
		sudo tee "$CHARGE_UNIT" >/dev/null <<EOF
[Unit]
Description=Cap battery charge for longevity (TUXEDO)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo $CHARGE_VAL > $CHARGE_PATH'

[Install]
WantedBy=multi-user.target
EOF
		sudo systemctl daemon-reload
		sudo systemctl enable --now battery-charge-limit.service
		echo "  charge limit set: $CHARGE_VAL -> $CHARGE_PATH (persisted)."
	fi
fi

# ---------------------------------------------------------------------------
banner "8/10  Login shell (zsh) + autologin to tty1 → niri-session"
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
# `|| true`: under set -e a getpwnam miss (NSS/LDAP-only or odd container user)
# would otherwise abort the whole script here.
CURRENT_SHELL="$(getent passwd "$CURRENT_USER" | cut -d: -f7 || true)"

# The whole tty1 → niri handoff lives in zsh's .zprofile; fish (the CachyOS
# default login shell) never sources it, so a fish login shell boots to a bare
# prompt + the CachyOS fastfetch greeting instead of niri. Make zsh the login
# shell so the very first reboot lands in niri. chsh prompts for THIS user's
# password (not sudo) and takes effect at next login.
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

# Silence the CachyOS fish fastfetch greeting — belt-and-suspenders so that if
# you ever do land in fish (a subshell, or before the chsh above), it isn't the
# "bad UI". config.fish sources the CachyOS config (which sets fish_greeting to
# fastfetch) first, so a no-op redefinition appended at the end wins. Idempotent.
FISH_CFG="$HOME/.config/fish/config.fish"
if [[ -f "$FISH_CFG" ]] && ! grep -q 'function fish_greeting; *end' "$FISH_CFG"; then
	printf '\n# silence CachyOS fastfetch greeting (added by .dotfiles setup.sh)\nfunction fish_greeting; end\n' >> "$FISH_CFG"
	echo "  silenced fish fastfetch greeting in $FISH_CFG."
fi

# DM model diverges by distro:
#   CachyOS — no display manager: disable any DM + getty@tty1 autologin, and
#     zsh's .zprofile execs niri --session on tty1 (handled below).
#   TUXEDO OS / Debian — keep SDDM; niri is installed as a selectable Wayland
#     session (debian/provision.sh). Pick "Niri" at login; KDE Plasma is the
#     fallback. So we do NOT disable the DM or write a getty autologin here.
if is_debian; then
	echo "  Debian/Tuxedo OS: SDDM stays; niri is a login session, not a tty1 handoff."
	echo "  Pick the 'Niri' session at the SDDM screen (KDE Plasma = fallback)."
else
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
fi

# ---------------------------------------------------------------------------
banner "9/10  systemd-oomd (kill runaway agents before swap death-spiral)"
# ---------------------------------------------------------------------------
# Without oomd: one Codex/agent eats all RAM → kernel OOM-killer fires
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
banner "10/10  sudo password feedback (show '*' while typing)"
# ---------------------------------------------------------------------------
# CachyOS/Arch sudo is silent while typing the password; pwfeedback echoes '*'
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
	echo "$STEP. Login shell was set to zsh in step 8 (re-login or reboot to apply)."
	echo "   If you skipped it: chsh -s \"\$(command -v zsh)\""
fi
STEP=$((STEP + 1))

echo
echo "$STEP. Verify SSH-over-GPG can talk to GitHub (after the keys are added):"
echo "   ssh -T git@github.com"
STEP=$((STEP + 1))

echo
if is_macos; then
	echo "$STEP. Restart to apply the Caps→Cmd LaunchAgent + shell change:"
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
	echo "   niri msg version                            # niri up"
	echo "   ghostty --version                           # terminal up"
	echo "   glxinfo | grep 'OpenGL renderer'            # AMD Radeon 890M (iGPU)"
	echo "   ls /sys/class/leds/ | grep kbd_backlight    # tuxedo-drivers keyboard LED"
	echo "   systemctl status tailord                    # fan-control daemon"
fi

echo
