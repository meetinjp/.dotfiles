# .dotfiles

Personal Ubuntu desktop and development configuration, managed with GNU Stow.
The desktop uses niri, Noctalia, and Ghostty. Shared terminal tools also have a
macOS profile. Borrow individual packages or adapt a profile to your machine.

## Install configurations

Install prerequisites, then clone without sudo:

```sh
sudo apt install git stow python3
git clone https://github.com/meetinjp/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
git submodule update --init nvim/.config/nvim
./install.sh --dry-run
./install.sh
```

The default `core` profile links configurations only. It does not install
software, use sudo, authenticate accounts, or enable services. Existing files
that conflict are preserved; resolve them before applying the profile.

Choose individual packages instead:

```sh
./install.sh --dry-run zsh tmux
./install.sh zsh tmux
./install.sh --delete zsh tmux
```

`--delete` removes managed links, not source files. It does not restore earlier
personal configurations or reverse separately requested setup tasks.

## Profiles

| Profile | Contents |
| --- | --- |
| `core` | Ghostty, Neovim, Prettier, ripgrep, Starship, tmux, zsh |
| `desktop` | Core plus Linux helpers, niri, kanshi, user units, Zen preferences |
| `macos` | Core plus Ruby configuration |
| `agents` | Personal Claude skills; shared Caveman setup is separate |

Profile package lists live in [profiles/](profiles/). App directories mirror
paths under your home directory. For example, `tmux/.config/tmux/tmux.conf`
becomes `~/.config/tmux/tmux.conf`. The checkout may live outside `~/.dotfiles`.

## Ubuntu desktop

Read [Ubuntu setup](ubuntu/README.md), review
[niri host preferences](niri/.config/niri/host.kdl) and
[display profiles](kanshi/.config/kanshi/config), then preview:

```sh
./install.sh --profile desktop --dry-run
./install.sh --profile desktop
```

The current Ubuntu-derived machine is verified. Stock Ubuntu 24.04 needs newer
Qt packages for the pinned Noctalia shell; provisioning checks this first.
Existing hardware drivers, display managers, and power policy remain OS-owned.

## Optional setup

- [Ubuntu software provisioning](ubuntu/README.md): explicit package installation.
- [macOS prerequisites](docs/macos.md): Homebrew and the `macos` profile.
- `./setup.sh git`: identity configuration that preserves unrelated Git settings.
- `./setup.sh keys`: GPG signing and SSH-over-GPG; private keys remain outside Git.
- `./setup.sh system`: optional keyboard, locale, login-shell, and system preferences.
- [Agent tools](agent-skills/README.md): shared skills and Codex/Claude preferences.
- [Noctalia settings and sleep protection](noctalia/README.md): separately enabled.
- [Proton Drive](scripts/proton-drive/README.md): deliberate two-way folder sync.

## Maintain

Run `./scripts/check.sh` before committing. CI runs shell checks and isolated
Python integration tests; it does not provision a complete desktop. See
[maintenance](docs/maintenance.md) for updates, conflicts, and machine-local data.

Neovim and Caveman are pinned upstream submodules. Initialize only the modules
you use, or run `git submodule update --init --recursive` for both.

[MIT license](LICENSE). Third-party submodules retain their own licenses.
