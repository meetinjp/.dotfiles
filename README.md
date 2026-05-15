# .dotfiles

Personal config for Arch Linux (desktop + WSL2). Managed with
[GNU stow](https://www.gnu.org/software/stow/).

## Layout

| Dir         | Purpose                                                      | How it lands           |
| ----------- | ------------------------------------------------------------ | ---------------------- |
| `git/`      | gitconfig templates (identity injected at setup time)        | rendered by `setup.sh` |
| `zsh/`      | bare zshrc — starship prompt, vi mode, nvm/bun/pnpm          | stowed                 |
| `starship/` | cross-shell prompt config                                    | stowed                 |
| `nvim/`     | submodule → [meetinjp/nvim](https://github.com/meetinjp/nvim) | stowed                |
| `wezterm/`  | terminal config (Linux + WSL)                                | stowed                 |
| `ripgrep/`  | `.ripgreprc` (smart-case, hidden, vcs/vendor ignores)        | stowed                 |
| `hyprland/` | Wayland compositor (Linux desktop only)                      | stowed                 |
| `waybar/`   | status bar (Linux desktop only)                              | stowed                 |
| `tofi/`     | app launcher (Linux desktop only)                            | stowed                 |
| `prettier/` | global prettier config                                       | stowed                 |
| `claude/`   | Claude Code config patcher + plugin installer                | run by `install.sh`    |
| `wsl/`      | `.wslconfig` (Windows host) + `etc/wsl.conf` (inside distro) | manual copy            |

## Install

### Prereqs

Base packages (all platforms):

```
git stow curl zsh starship zsh-autosuggestions zsh-syntax-highlighting \
  neovim ripgrep gcc python3 unzip eza gnupg
```

Linux desktop additions:

```
hyprland wezterm waybar tofi yazi firefox wl-clipboard pavucontrol keyd brightnessctl gdb
```

Fonts (for starship + wezterm glyphs):
[FiraCode Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/latest).

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
3. Run setup. Pass identity via env vars (or run bare and answer
   prompts):
   ```
   GIT_NAME="meetinjp" \
   GIT_EMAIL="you@example.com" \
   GIT_WORK_EMAIL="you@work.example" \
   ~/.dotfiles/setup.sh
   ```
   `setup.sh` renders `~/.gitconfig` (+ `~/.gitconfig-work` if you set
   the work email) from `git/*.template`, generates an Ed25519 GPG key
   with sign + auth subkeys, registers the auth subkey for SSH-over-GPG,
   and prints the public keys to paste on GitHub.

   Non-interactive runs (no TTY) skip the keyd / locale prompts; pass
   `DOTFILES_YES=1` to auto-accept defaults.
4. Post-deps:
   - [NVM](https://github.com/nvm-sh/nvm?tab=readme-ov-file#installing-and-updating)
     for node version pinning
5. Reopen the terminal — starship prompt + SSH-over-GPG go live.

### SSH-over-GPG (one key for everything)

`setup.sh` provisions a single Ed25519 GPG key that does both jobs:

- **Commit / tag signing** — primary `[C]` + sign `[S]` subkey.
- **SSH auth** — `[A]` subkey, served by gpg-agent's SSH socket. No
  `~/.ssh/id_ed25519` is generated; `ssh` talks to gpg-agent via
  `SSH_AUTH_SOCK` (exported by `~/.zshrc`).

You still upload **two** keys to GitHub — same underlying private key,
two different public formats:

- https://github.com/settings/gpg/new — armored GPG export, used to
  verify commit signatures.
- https://github.com/settings/ssh/new — output of `gpg --export-ssh-key`,
  used so `git push` over SSH authenticates against gpg-agent.

`setup.sh` prints both blocks at the end of its run.

### Troubleshooting

- `existing target is not owned by stow`: `unlink` (or `rm`) the target
  and rerun `install.sh`.
- `Permission denied (publickey)` on `git push`: confirm
  `SSH_AUTH_SOCK` points at gpg-agent — `echo $SSH_AUTH_SOCK` should
  match `gpgconf --list-dirs agent-ssh-socket`. If not, restart the
  shell or run `gpgconf --launch gpg-agent`.

## WSL2

WSL settings live in two files, both copied by hand (neither is stowed
because their final paths aren't under `$HOME`):

| Source in repo               | Final path                                     |
| ---------------------------- | ---------------------------------------------- |
| `wsl/.wslconfig`             | `%USERPROFILE%\.wslconfig` (Windows host)      |
| `wsl/etc/wsl.conf.template`  | rendered by `setup.sh` to `wsl/etc/wsl.conf`, then `sudo cp` to `/etc/wsl.conf` |

`wsl.conf.template` carries a `${WSL_USER}` placeholder for the
`default=` user. `setup.sh` fills it from `$WSL_USER` (env var) or the
current Linux user, writes the rendered `wsl.conf` next to the
template, and prints the `sudo cp` command. The rendered file is
gitignored so the public repo never carries a real username.

After copying either file, `wsl.exe --shutdown` from Windows and
reopen the distro.

### Renaming the WSL user

`wsl/etc/wsl.conf` defaults to `meetinjp`. If the user account inside
your distro is different (e.g. the installer-default `username` you
picked on first launch), either edit the wsl.conf before copying, or
rename the existing user.

Renaming can't be done from inside the distro being renamed — the
user must have no running processes. From **Windows PowerShell**,
after closing every WSL terminal:

```powershell
wsl -d archlinux -u root
```

Inside the root shell that opens, substituting `OLD_USER` (the
current Linux username) and `NEW_USER`:

```bash
usermod -l NEW_USER -d /home/NEW_USER -m OLD_USER
groupmod -n NEW_USER OLD_USER
sed -i "s/default=OLD_USER/default=NEW_USER/" /etc/wsl.conf
exit
```

Back at PowerShell:

```powershell
wsl --shutdown
wsl -d archlinux
```

The distro reopens with the new user and home directory. Re-run
`~/.dotfiles/install.sh` from the new home to refresh stow symlinks.

## Extra

### Nvidia Optimus (GPU switching)

- [EnvyControl](https://github.com/bayasdev/envycontrol?tab=readme-ov-file#%EF%B8%8F-getting-envycontrol)

### Bluetooth (Linux desktop)

```
sudo pacman -S bluez bluez-utils
sudo systemctl enable --now bluetooth.service
```
