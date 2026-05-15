# .dotfiles

Personal config for Arch Linux (desktop + WSL2). Managed with
[GNU stow](https://www.gnu.org/software/stow/).

## Layout

| Dir         | Purpose                                                        | How it lands           |
| ----------- | -------------------------------------------------------------- | ---------------------- |
| `git/`      | gitconfig + work-email `includeIf`                             | copied by `setup.sh`   |
| `zsh/`      | zshrc (Oh-My-Zsh, vi-mode, nvm/bun/pnpm, claude path)          | stowed                 |
| `nvim/`     | submodule → [meetinjp/nvim](https://github.com/meetinjp/nvim)  | stowed                 |
| `wezterm/`  | terminal config (Linux + WSL)                                  | stowed                 |
| `ripgrep/`  | `.ripgreprc` (smart-case, hidden, vcs/vendor ignores)          | stowed                 |
| `yazi/`     | file manager invoked from hyprland + CLI                       | stowed                 |
| `zellij/`   | terminal multiplexer (lunar/cavecrew layouts)                  | stowed                 |
| `hyprland/` | Wayland compositor (Linux desktop only)                        | stowed                 |
| `waybar/`   | status bar (Linux desktop only)                                | stowed                 |
| `tofi/`     | app launcher (Linux desktop only)                              | stowed                 |
| `prettier/` | global prettier config                                         | stowed                 |
| `claude/`   | Claude Code config patcher + plugin installer                  | run by `install.sh`    |
| `wsl/`      | `.wslconfig` (Windows host) + `etc/wsl.conf` (inside distro)   | manual copy            |

## Install

### Prereqs

Base packages (all platforms):

```
git stow curl zsh neovim ripgrep gcc python3 unzip eza
```

Linux desktop additions:

```
hyprland wezterm waybar tofi yazi firefox wl-clipboard pavucontrol keyd brightnessctl gdb
```

### Steps

1. Clone recursively into `~/.dotfiles`:
   ```
   git clone --recursive git@github.com:meetinjp/.dotfiles ~/.dotfiles
   ```
2. Run the installer (stows packages, patches `~/.claude.json`,
   user-installs the `caveman` Claude Code plugin):
   ```
   ~/.dotfiles/install.sh
   ```
   `~/.claude.json` is live-mutated by Claude Code so it can't be stowed —
   the patcher merges the dotfiles-owned keys idempotently instead.
3. Run setup (git config templates, locale, SSH/GPG keys, keyd):
   ```
   ~/.dotfiles/setup.sh
   ```
   Non-interactive runs (no TTY) skip all prompts; pass `DOTFILES_YES=1` to
   auto-accept defaults. After SSH/GPG generation, paste the printed
   pubkeys at:
   - SSH: https://github.com/settings/ssh/new
   - GPG: https://github.com/settings/gpg/new
4. Post-deps:
   - [Oh My Zsh](https://ohmyz.sh/#install)
   - [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md#oh-my-zsh)
   - [NVM](https://github.com/nvm-sh/nvm?tab=readme-ov-file#installing-and-updating)
   - [FiraCode Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases)
     (used by wezterm)

### WSL2

WSL settings live in two files, both copied by hand (neither is stowed
because their final paths aren't under `$HOME`):

| File                       | Final path on Windows / in the distro          |
| -------------------------- | ---------------------------------------------- |
| `wsl/.wslconfig`           | `%USERPROFILE%\.wslconfig` (Windows host)      |
| `wsl/etc/wsl.conf`         | `/etc/wsl.conf` (inside the WSL distro)        |

After editing either, run `wsl.exe --shutdown` from the Windows host
and reopen the distro.

### Troubleshooting

- `existing target is not owned by stow`: `unlink` (or `rm`) the target
  and rerun `install.sh`.

## Extra

### Nvidia Optimus (GPU switching)

- [EnvyControl](https://github.com/bayasdev/envycontrol?tab=readme-ov-file#%EF%B8%8F-getting-envycontrol)

### Bluetooth (Linux desktop)

```
sudo pacman -S bluez bluez-utils
sudo systemctl enable --now bluetooth.service
```
