# zsh login-shell startup. Only sourced for login shells.
#
# No display manager: getty@tty1 autologins this user (configured by
# setup.sh as a systemd drop-in). From there, control lands here — and if
# we're on tty1 with no Wayland session up, hand off to niri.
#
# `exec niri --session` replaces zsh; when niri exits, the login shell is
# gone and getty re-spawns. Because autologin is enabled, .zprofile fires
# again → niri restarts. tty2..tty6 stay plain text consoles you can
# Ctrl+Alt+F2..F6 into for emergency shells.

# Homebrew (macOS / Linuxbrew). Put brew + its tools on PATH for login shells;
# `brew shellenv` also exports HOMEBREW_PREFIX, which .zshrc uses to locate the
# zsh plugins. Probes each known prefix — Apple Silicon, Intel, Linuxbrew — and
# the first that exists wins. No-op on hosts without Homebrew (e.g. pacman Arch).
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [[ -x "$_brew" ]] && eval "$("$_brew" shellenv)" && break
done
unset _brew

# Put user bin dirs on PATH for LOGIN shells, not just interactive (.zshrc) ones.
# The niri session is launched by a login, non-interactive shell (niri-session →
# `exec -l "$SHELL"` / `exec niri --session`), which sources THIS file but never
# .zshrc — so without this, GUI apps niri spawns that live under ~/.local/bin
# (e.g. `zen-browser`) or ~/.cargo/bin are not found and silently fail to start.
# Idempotent; rustup's ~/.zshenv already adds ~/.cargo/bin, we just guarantee it.
for _d in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    case ":$PATH:" in *":$_d:"*) ;; *) [[ -d "$_d" ]] && PATH="$_d:$PATH" ;; esac
done
unset _d
export PATH

# tty1 → niri handoff is Linux/Wayland only. macOS has no VT named /dev/tty1
# and no niri, so the tty test already fails there — the $OSTYPE guard makes
# that explicit and prevents an accidental `exec niri` on Darwin.
if [[ "$OSTYPE" == linux* ]] && [[ -z "$WAYLAND_DISPLAY" ]] && [[ -z "$DISPLAY" ]] && [[ "$(tty)" = "/dev/tty1" ]]; then
    # niri --session sets dbus + XDG env + dbus-activation env itself.
    # Avoid the bundled `niri-session` wrapper: it tries
    # `systemctl --user --wait start niri.service` which hangs on a
    # first-boot user-systemd that has no graphical-session.target wiring.
    exec niri --session
fi
