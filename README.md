# .dotfiles

Personal config for [CachyOS](https://cachyos.org/) on a laptop. Wayland
session is [niri](https://github.com/niri-wm/niri); shell-on-niri is
[Noctalia](https://github.com/noctalia-dev/noctalia-shell) (Quickshell
bar + launcher + notifications + lock + polkit + wallpaper rolled into
one); terminal is [Ghostty](https://ghostty.org/); shell is zsh. No
display manager — getty@tty1 autologins, and zsh's `.zprofile` execs
`niri --session` directly. Managed with
[GNU stow](https://www.gnu.org/software/stow/).

> **On macOS?** The CLI/dev half of this repo is cross-platform; the Linux
> desktop is not. Skip the CachyOS/pacman sections below and jump to
> **[macOS (Xcode box)](#macos-xcode-box)** — `install.sh` runs `brew bundle`
> and stows everything in one shot, and that section has a full **React Native
> / iOS** build walkthrough (Xcode 26, rbenv Ruby, CocoaPods, iPad).

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

## macOS (Xcode box)

The CLI/dev half of this repo is cross-platform. The Linux **desktop** —
niri, kanshi, wlsunset, Noctalia, the Win11 KVM VM, Nvidia `prime-run` — has
no macOS equivalent and is intentionally skipped there; macOS ships native
screenshots, display arrangement, and GPU management. `install.sh` and
`setup.sh` branch on `uname`, so the same scripts run on both OSes.

```sh
# 1. Command Line Tools + Homebrew (prerequisites for everything below)
xcode-select --install                       # git, clang, make
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Clone WITHOUT sudo — sudo makes the repo root-owned and breaks git + stow.
#    Clone over HTTPS; a fresh box has no SSH key yet.
git clone https://github.com/meetinjp/.dotfiles.git ~/.dotfiles

#    The nvim config is a submodule with an SSH URL. Before your key is on
#    GitHub, initialise it over HTTPS (otherwise ~/.config/nvim is empty):
git -C ~/.dotfiles -c url."https://github.com/".insteadOf="git@github.com:" \
    submodule update --init --recursive

# 3. install.sh runs `brew bundle` (the WHOLE Brewfile — the "pacman -S"
#    equivalent: full CLI + React Native/iOS toolchain) and then stows configs.
~/.dotfiles/install.sh

# 4. Identity + GPG/SSH (auto-skips the Linux keyd/getty/oomd steps)
GIT_NAME="meetinjp" GIT_EMAIL="you@example.com" ~/.dotfiles/setup.sh

# 5. Self-installing runtimes not in Homebrew (manage their own ~/ dirs)
curl -fsSL https://bun.sh/install | bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

What the macOS branches do differently:

| Concern        | Linux                          | macOS                                                        |
| -------------- | ------------------------------ | ------------------------------------------------------------ |
| Packages       | pacman / paru                  | Homebrew (`Brewfile`); `brew shellenv` probes `/opt/homebrew` + `/usr/local` |
| zsh plugins    | `/usr/share/zsh/plugins`       | `$HOMEBREW_PREFIX/share` (probed in `.zshrc`)                |
| SSH auth       | gpg-agent (`gpgconf` socket)   | **same** — gpg-agent parity, `pinentry-mac` auto-pinned       |
| Caps → Ctrl    | keyd (`/etc/keyd`)             | `hidutil` LaunchAgent (`~/Library/LaunchAgents`)             |
| Firefox `user.js` | stowed to `~/.config`       | symlinked into `~/Library/Application Support/Firefox`       |
| Ghostty extras | `gtk-*` / `linux-cgroup` keys  | `config-macos.conf` (cmd keybinds) via App Support include    |
| Desktop / VM   | niri, kanshi, prime-run, KVM   | skipped — use native macOS                                   |

zsh is already the default shell on macOS (Catalina+), and Apple's `/bin/zsh`
is fine. Homebrew's zsh is **not** in the `Brewfile`, so switch to it only if
you `brew install zsh` **first** — otherwise `chsh` points your login shell at
a missing binary and the shell breaks on the next login:

```sh
brew install zsh                                   # REQUIRED first — not in the Brewfile
echo "$(brew --prefix)/bin/zsh" | sudo tee -a /etc/shells
chsh -s "$(brew --prefix)/bin/zsh"
```

Broke your shell this way? Recover with `chsh -s /bin/zsh`.

Grant Ghostty Accessibility permission for the quick-terminal global hotkey to
fire (System Settings → Privacy & Security → Accessibility).

### Ruby (rbenv — the "nvm for Ruby")

Apple's system Ruby is 2.6 and deprecated; never `gem install` against it.
`rbenv` (in the `Brewfile`, initialised in `.zshrc`) is the Ruby analog of nvm:
it installs and switches between arbitrary Ruby versions — modern *and* legacy
— and auto-selects per directory from a project's `.ruby-version`.

```sh
rbenv install -l                 # list installable versions
rbenv install 3.4.9              # install one (ruby-build compiles it)
rbenv global 3.4.9              # default for new shells
cd some/project && rbenv local 3.2.6   # pin this dir (writes .ruby-version)
ruby -v                          # confirms the shim resolved
```

`bundler` is installed into every Ruby automatically by the
`rbenv-default-gems` plugin (driven by the stowed `~/.rbenv/default-gems`).
`~/.gemrc` (stowed from `ruby/`) sets `--no-document` so installs are fast. The
`openssl@3` / `libyaml` / `readline` build deps are in the `Brewfile` so
`ruby-build` can compile any version without missing-header errors.

> **Legacy Rubies (< 3.1):** these predate OpenSSL 3 and modern Clang and can
> fail to build. Fixes, in order of preference: pick the newest patch of that
> minor line (e.g. `3.0.7` over `3.0.0`); or pass build flags, e.g.
> `RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@3)" rbenv install 2.7.8`.
> See the ruby-build wiki's "Troubleshooting" if a specific version still fails.

### React Native / iOS (macOS)

The `Brewfile` installs the native-build stack: `node`, `watchman`, the `rbenv`
Ruby toolchain above, `ccache`, `git-lfs`, `xcbeautify`, `ios-deploy`, and
`fastlane`. **CocoaPods is intentionally _not_ a Homebrew formula** — brew runs
it on its own Ruby, so `pod` and `bundle exec pod` would resolve to different
versions; it's installed through the app's `Gemfile` instead (below). **Xcode
is not a Homebrew package** either and must be installed separately.

**Xcode 26 on Intel.** Xcode 26 is a *Universal* binary and runs on the Intel
Macs macOS 26 Tahoe still supports (MacBook Pro 16″ 2019 / 13″ 2020, iMac 2020,
Mac Pro 2019) — it needs macOS Sequoia 15.6+ (Xcode 26.0–26.3) or Tahoe 26.2+
(26.4.1/26.5). ⚠️ **Do not install it via the `xcodes` CLI or the App Store on
an Intel Mac** — both can deliver the *arm64-only* `.xip`, which fails to launch
with `Bad CPU type in executable`. Instead grab the **Universal** build
manually:

```sh
# 1. Download the larger "Universal" Xcode 26 .xip (~2.6 GB, vs ~2.0 GB arm64)
#    from https://developer.apple.com/download/all/ (sign in with your Apple ID).
# 2. Expand + install:
xip --expand ~/Downloads/Xcode_26.x.xip
sudo mv Xcode.app /Applications/

# 3. Verify it's actually x86_64/universal (the whole point):
file /Applications/Xcode.app/Contents/MacOS/Xcode    # must say x86_64 or universal

# 4. Point the toolchain at it + accept the license + finish first-launch setup:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version                                   # → Xcode 26.x
```

(AI / Coding-Intelligence features are disabled on Intel, but the compiler,
Simulator, and device pipeline all work.)

**Build the app** (legacy CocoaPods-based RN):

```sh
cd path/to/your-rn-app
rbenv install "$(cat .ruby-version)"     # match the project's Ruby
bundle install                            # project's pinned cocoapods/fastlane
nvm install 20 && nvm use 20              # legacy RN wants Node 18/20 LTS — brew's node is too new
npm install                               # or yarn / pnpm, per the lockfile (honor .nvmrc/engines)
bundle exec pod install --project-directory=ios

# iPad simulator:
xcrun simctl list devices | grep -i ipad           # pick a booted/available iPad
npx react-native run-ios --simulator="iPad (A16)"  # name from the list above

# Physical iPad (tethered): open ios/<App>.xcworkspace in Xcode, set your
# signing Team once, then:
npx react-native run-ios --device
```

Always open the **`.xcworkspace`** (not the `.xcodeproj`) once CocoaPods has
run. If a pod ships an arm64-only `.xcframework`, Simulator builds may fail to
link — run `xcodebuild -downloadPlatform iOS` or build for a device instead.

If the iOS build fails in the **"Bundle React Native code and images"** phase
with `node: command not found`, that's because Xcode build phases don't read
your shell config (so `nvm`/Homebrew `node` aren't on their `PATH`). Point the
app's `ios/.xcode.env` at an absolute path: `export NODE_BINARY=$(command -v node)`.

> Heads-up: macOS 27 will be Apple-Silicon-only, and CocoaPods goes read-only in
> Dec 2026. Fine for a legacy app with a locked `Podfile.lock`, but this Intel
> box is a last-generation platform — plan accordingly for long-term work.

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

- **macOS — `fatal: detected dubious ownership` / can't edit repo files**: the
  repo was cloned with `sudo` and is owned by `root`. Fix it with
  `sudo chown -R "$(whoami):staff" ~/.dotfiles` (and never clone with `sudo`).
- **macOS — Neovim opens bare (no plugins / no highlighting)**: the
  `nvim/.config/nvim` submodule wasn't initialised (its remote is an SSH URL,
  which fails before your key is on GitHub). Init it over HTTPS:
  `git -C ~/.dotfiles -c url."https://github.com/".insteadOf="git@github.com:" submodule update --init --recursive`.
- **macOS — no syntax highlighting / missing `node`, `eza`, etc.**: `brew bundle`
  was never run. `~/.dotfiles/install.sh` now does it automatically; or run
  `brew bundle --file=~/.dotfiles/Brewfile` directly.
- **macOS — shell broken after switching to Homebrew zsh** (login falls back or
  errors): you ran `chsh -s "$(brew --prefix)/bin/zsh"` without `brew install
  zsh` first, so the login shell points at a nonexistent binary. Recover with
  `chsh -s /bin/zsh` (Apple's system zsh, always present).
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
