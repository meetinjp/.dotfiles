# .dotfiles

Personal config for [CachyOS](https://cachyos.org/) on a laptop. Wayland
session is [niri](https://github.com/niri-wm/niri); shell-on-niri is
[Noctalia](https://github.com/noctalia-dev/noctalia-shell) (Quickshell
bar + launcher + notifications + lock + polkit + wallpaper rolled into
one); terminal is [Ghostty](https://ghostty.org/); shell is zsh. No
display manager — getty@tty1 autologins, and zsh's `.zprofile` execs
`niri --session` directly. Managed with
[GNU stow](https://www.gnu.org/software/stow/).

Hybrid-GPU target (AMD iGPU + Nvidia dGPU laptops). Niri renders on the
AMD iGPU; the Nvidia card sleeps until `prime-run` wraps a process. Keeps
Wayland-on-Nvidia headaches out of the desktop while leaving full GPU
power available for games / CUDA. Machine-specific bits (panel output
name, scale, GPU PCI path) are flagged in the config files for per-host
adjustment.

Touchpad uses libinput `button-areas` click-method (bottom-right press = R
click, Windows/PC style) plus tap-to-click on top (2-finger tap also R).
Default browser is `firefox-developer-edition`, set both via xdg-mime and
the `$BROWSER` env var (for CLI tools like `gh` and `man`).

## Layout

| Dir         | Purpose                                                      | How it lands           |
| ----------- | ------------------------------------------------------------ | ---------------------- |
| `bin/`      | `~/.local/bin/` scripts (`prime-run`, `niri-screenshot`)     | stowed                 |
| `claude/`   | Claude Code config patcher + plugin installer                | run by `install.sh`    |
| `ghostty/`  | GPU-accelerated terminal (Gruvbox Dark Hard, zsh integration)| stowed                 |
| `git/`      | gitconfig templates (identity injected at setup time)        | rendered by `setup.sh` |
| `kanshi/`   | auto-switch monitor profiles (laptop / docked)               | stowed                 |
| `niri/`     | Wayland compositor — scrollable tiling                       | stowed                 |
| `nvim/`     | submodule → [meetinjp/nvim](https://github.com/meetinjp/nvim) | stowed                |
| `prettier/` | global prettier config                                       | stowed                 |
| `ripgrep/`  | `.ripgreprc` (smart-case, hidden, vcs/vendor ignores)        | stowed                 |
| `starship/` | cross-shell prompt config                                    | stowed                 |
| `tmux/`     | `C-a` prefix, mouse on, vim nav, Gruvbox status              | stowed                 |
| `zsh/`      | bare zshrc + `.zprofile` (tty1 → niri handoff)               | stowed                 |

Bar / launcher / notifications / lock / polkit / wallpaper are all
provided by **Noctalia** (the `cachyos-niri-noctalia` package). No
per-component config in this repo — Noctalia ships its own defaults
and is configured at runtime via its own settings UI.

## Install

### 1. Base packages

Bootstrap (smallest set so `git clone` + `stow` work):

```sh
sudo pacman -S --needed git stow base-devel
```

Then the full stack. Split into official-repo and AUR groups:

```sh
sudo pacman -S --needed \
    niri xwayland-satellite ghostty kanshi wlsunset \
    cachyos-niri-noctalia noctalia-shell noctalia-qs \
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring \
    brightnessctl wl-clipboard cliphist grim slurp \
    pavucontrol playerctl pamixer power-profiles-daemon udisks2 keyd \
    xdg-utils libnotify \
    zsh tmux starship zsh-autosuggestions zsh-syntax-highlighting \
    neovim ripgrep eza yazi curl unzip gnupg gcc python python-pip \
    nodejs npm rustup go docker docker-compose \
    ttf-firacode-nerd noto-fonts noto-fonts-emoji noto-fonts-cjk
```

AUR (CachyOS ships `paru` by default):

```sh
paru -S firefox-developer-edition
```

`cachyos-niri-noctalia` is the curated preset that pulls Noctalia (the
Quickshell-based niri shell handling bar, launcher, notifications,
lock, polkit, and wallpaper).

Node version manager + Bun (canonical install scripts — they manage their
own dirs under `~/.nvm` and `~/.bun`):

```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
curl -fsSL https://bun.sh/install | bash
```

Python toolchain (uv — fast pip+venv replacement):

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 2. Clone + stow

Fresh machine has no SSH key yet, so clone over HTTPS first. After
`setup.sh` provisions SSH-over-GPG you can switch the remote to SSH.

```sh
git clone --recursive https://github.com/meetinjp/.dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

Later, once `ssh -T git@github.com` works:

```sh
git -C ~/.dotfiles remote set-url origin git@github.com:meetinjp/.dotfiles.git
```

`install.sh` symlinks every package into `~`, runs the Claude Code config
patcher, and installs the `caveman` Claude plugin user-globally.

### 3. Identity + system setup

```sh
GIT_NAME="meetinjp" \
GIT_EMAIL="you@example.com" \
GIT_WORK_EMAIL="you@work.example" \
~/.dotfiles/setup.sh
```

Or run bare and answer prompts. Pass `DOTFILES_YES=1` to auto-accept
defaults in non-interactive runs.

`setup.sh` does, in order:

1. Asks for git identity.
2. Renders `~/.gitconfig` (+ `~/.gitconfig-work` if `GIT_WORK_EMAIL` is set).
3. Generates `en_US.UTF-8` locale.
4. Generates an Ed25519 GPG key with sign + auth subkeys.
5. Configures gpg-agent to serve the auth subkey as an ssh-agent.
6. Installs `/etc/keyd/default.conf` with Caps Lock → Ctrl, enables keyd.
7. Disables any existing display manager + installs a `getty@tty1`
   autologin drop-in for this user. zsh's `.zprofile` then execs
   `niri --session` on tty1 when no Wayland session is up.
8. Enables `systemd-oomd` with a `user@.service` drop-in that kills
   the heaviest user cgroup under memory pressure (multi-agent OOM
   resilience).

Then prints the GPG / SSH public keys + a checklist of next steps.

### 4. Switch shell + reboot

```sh
chsh -s /bin/zsh
sudo systemctl reboot
```

After reboot, systemd autologins you on tty1, your zsh `.zprofile`
detects tty1 + no Wayland, and `exec`s `niri --session`. Because exec
replaces zsh, when niri exits the login shell is gone too — getty
re-spawns and autologin re-fires, so niri restarts automatically.
For an emergency shell switch to tty2..tty6 (`Ctrl+Alt+F2..F6`).

## SSH-over-GPG (one key for everything)

`setup.sh` provisions a single Ed25519 GPG key that does both jobs:

- **Commit / tag signing** — primary `[C]` + sign `[S]` subkey.
- **SSH auth** — `[A]` subkey, served by gpg-agent's SSH socket. No
  `~/.ssh/id_ed25519` is generated; `ssh` talks to gpg-agent via
  `SSH_AUTH_SOCK` (exported by `~/.zshrc`).

You upload **two** keys to GitHub — same underlying private key, two
different public formats:

- <https://github.com/settings/gpg/new> — armored GPG export, used to
  verify commit signatures.
- <https://github.com/settings/ssh/new> — output of `gpg --export-ssh-key`,
  used so `git push` over SSH authenticates against gpg-agent.

`setup.sh` prints both blocks at the end.

## Cheat sheets

### niri

- `Alt + Shift + /` — show the keybind overlay (read this first).
- `Alt + Q` — open Ghostty.
- `Alt + E` — open Yazi (file manager in Ghostty).
- `Alt + D` — Noctalia app launcher.
- `Alt + Shift + Q` — Noctalia session menu (logout / reboot / shutdown).
- `Alt + H/J/K/L` — focus column-left / window-down / window-up / column-right.
- `Alt + Ctrl + H/J/K/L` — move the focused column/window in that direction.
- `Alt + 1..9` — focus workspace; `Alt + Shift + 1..9` — move column to.
- `Alt + Shift + arrows` — focus monitor in that direction; add `Ctrl` to
  move the focused column across monitors. ws1 + ws2 are pinned to
  `HDMI-A-1` (external) when docked; ws3..9 stay on the laptop panel.
- `Alt + ,` / `Alt + .` — consume/expel a window from the current column.
- `Alt + R` — cycle preset column widths (1/3 → 1/2 → 2/3).
- `Alt + F` — maximize column; `Alt + Shift + F` — true fullscreen.
- `Alt + W` — toggle column tabbed display.
- `Alt + V` — toggle floating.
- `Alt + O` — overview.
- `Alt + C` — close window.
- `Super + L` — Noctalia lock (uses Super not Alt so it doesn't shadow focus-right).
- `Print` — interactive screenshot (region by default).

Full reference: <https://github.com/niri-wm/niri/wiki/Configuration:-Key-Bindings>.

### Ghostty

- `Ctrl + Shift + T` — new tab (inherits current cwd via shell-integration).
- `Ctrl + Shift + Alt + T` — rename current tab (`prompt_tab_title`).
- `Ctrl + Shift + H/L` — previous/next tab; `Ctrl + 1..9` — jump.
- `Ctrl + Shift + Enter` — split right; `Ctrl + Shift + D` — split down.
- `Ctrl + Shift + J/K` — focus next/previous split.
- `Ctrl + Shift + Z` — zoom split; `F11` — fullscreen.
- `Ctrl + Shift + ,` — reload config.
- ``Super + ` `` — toggle quick-terminal (dropdown from top).

Full reference: <https://ghostty.org/docs/config/keybind/reference>.

## Nvidia / prime-run

Niri renders on the AMD iGPU. To run a single process on the Nvidia dGPU,
prefix with `prime-run` (script lives in `bin/.local/bin/prime-run`):

```sh
prime-run firefox-developer-edition
prime-run blender
prime-run steam
prime-run glxinfo | grep "OpenGL renderer"      # confirms Nvidia
```

For the desktop renderer the answer should be the AMD card — verify with
the unprefixed call: `glxinfo | grep "OpenGL renderer"`.

If the Nvidia card fights you (e.g. VRAM creep when something *does* run
on it), the well-known fix is described in
<https://github.com/niri-wm/niri/wiki/Nvidia>.

## Bluetooth

```sh
sudo pacman -S bluez bluez-utils
sudo systemctl enable --now bluetooth.service
```

## Housekeeping

`setup.sh` backs up the existing `~/.gitconfig` (+ `-work`) to
`~/.gitconfig.bak.<epoch>.<pid>` before re-rendering. Prune old backups
periodically:

```sh
find ~ -maxdepth 1 -name '.gitconfig*.bak.*' -mtime +30 -delete
```

## Troubleshooting

- `existing target is not owned by stow`: `unlink` (or `rm`) the target
  and rerun `install.sh`.
- `Permission denied (publickey)` on `git push`: confirm `SSH_AUTH_SOCK`
  points at gpg-agent — `echo $SSH_AUTH_SOCK` should match
  `gpgconf --list-dirs agent-ssh-socket`. If not, restart the shell or
  run `gpgconf --launch gpg-agent`.
- Niri starts on a blank screen with cursor only: Noctalia didn't
  launch. Open Ghostty with `Alt+Q` and run `qs -c noctalia-shell &`
  to start it manually. If that errors, check
  `pacman -Qq cachyos-niri-noctalia noctalia-qs noctalia-shell`.
- External monitor doesn't show up: `niri msg outputs` lists the real
  output name; update `kanshi/.config/kanshi/config` to match
  (`HDMI-A-1` and `DP-1` are the most common identifiers).
- Screen never warms at night: wlsunset is spawned with placeholder
  `0.00` coordinates. Edit the `spawn-at-startup "wlsunset"` line in
  `niri/.config/niri/config.kdl` with your real lat/long (decimal
  degrees), then reload niri or rerun `wlsunset` manually.
- Autologin doesn't fire: check
  `sudo systemctl cat getty@tty1` for the `ExecStart=` line containing
  `--autologin <yourname>`. If absent, rerun `setup.sh` (step 7
  installs the drop-in). Also verify no display manager is enabled:
  `systemctl is-enabled sddm gdm lightdm ly greetd`. Any "enabled"
  here will steal tty1 from autologin.
- Stuck at a zsh prompt on tty1 after boot (niri-session didn't fire):
  the `.zprofile` guard didn't match. Run `tty` (must say `/dev/tty1`)
  and `echo $WAYLAND_DISPLAY` (must be empty). Type `exec niri-session`
  to start it by hand.
