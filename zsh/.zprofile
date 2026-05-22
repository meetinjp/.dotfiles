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

if [[ -z "$WAYLAND_DISPLAY" ]] && [[ -z "$DISPLAY" ]] && [[ "$(tty)" = "/dev/tty1" ]]; then
    # niri --session sets dbus + XDG env + dbus-activation env itself.
    # Avoid the bundled `niri-session` wrapper: it tries
    # `systemctl --user --wait start niri.service` which hangs on a
    # first-boot user-systemd that has no graphical-session.target wiring.
    exec niri --session
fi
