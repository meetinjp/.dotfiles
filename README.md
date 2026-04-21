# .dotfiles

## Getting Started

### Linux

1. Install the prerequisites:
   ```
   git firefox stow curl neovim ripgrep wl-clipboard gcc gdb pavucontrol unzip python3 keyd brightnessctl yazi hyprland kitty tofi waybar
   ```
1. Clone this repo _recursively_ into your home directory:
   ```
   git clone --recursive git@github.com:meetinjp/.dotfiles ~/.dotfiles
   ```
1. Run the `install.sh` script:
   ```
   ~/.dotfiles/install.sh
   ```
1. After the installation is complete, run the `setup.sh` script:
   ```
   ~/.dotfiles/setup.sh
   ```
   This installs the Git config templates (personal + Lunar Logic via `includeIf`) and generates an Ed25519 SSH key and an Ed25519 GPG key (with UIDs for both emails) if they don't exist yet. Paste the printed pubkeys at:
   - SSH: https://github.com/settings/ssh/new
   - GPG: https://github.com/settings/gpg/new
1. Install the postrequisites:
   - `zsh`
   - [Oh My Zsh](https://ohmyz.sh/#install)
   - [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md#oh-my-zsh)
   - [Node Version Manager](https://github.com/nvm-sh/nvm?tab=readme-ov-file#installing-and-updating)
   - `neovim`
   - [FiraCode](https://github.com/tonsky/FiraCode)

#### Troubleshooting

- "existing target is not owned by stow": `unlink` or `rm` the given target and run the installation script again.

### Windows

1. Install the bootstrap prerequisites (everything needed to _run_ `install.ps1`):
   - `Git.Git`
   - `Neovim.Neovim`
   - `Microsoft.PowerShell` (optional — only if you want `pwsh` 7+)
1. Clone this repo _recursively_ into your home directory:
   ```
   git clone --recursive git@github.com:meetinjp/.dotfiles $HOME\.dotfiles
   ```
1. Run the `install.ps1` script in PowerShell:
   ```
   powershell -ExecutionPolicy Bypass -File $HOME\.dotfiles\install.ps1
   ```
   (or `pwsh` for PowerShell 7+). It:
   - installs the rest of the prerequisites via `winget` (Python, Go, Rustup, ripgrep) — idempotent, skips any already installed;
   - creates directory junctions for `nvim` and `prettier` configs;
   - stubs `$PROFILE` so PowerShell picks up the repo profile (which puts `~/.local/bin` on PATH for the Claude Code CLI).

   No admin or Developer Mode required. Open a new PowerShell session afterwards so the updated PATH takes effect, then run `nvim` and let Mason finish installing the language servers.
1. Run the `setup.ps1` script from PowerShell — it installs the Git config templates (personal + Lunar Logic via `includeIf`), generates SSH + GPG keys, and offers to remap Caps Lock → Ctrl (self-elevates via UAC just for that step):
   ```
   powershell -ExecutionPolicy Bypass -File $HOME\.dotfiles\setup.ps1
   ```
   Paste the printed pubkeys at https://github.com/settings/ssh/new and https://github.com/settings/gpg/new.

#### Troubleshooting

- "Target exists and is not a link": move or remove the offending path (e.g. `%LOCALAPPDATA%\nvim`) and rerun `install.ps1`.
- Profile stub not loaded: confirm which host you're in by checking `$PROFILE`, then rerun `install.ps1` from that host.
- Mason fails to install `python-lsp-server`, `ruff`, or `clang-format`: confirm `python --version` works in a _fresh_ PowerShell session (the Microsoft Store stub at `%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe` doesn't count — it only launches the Store). If `install.ps1` installed Python via winget but `python` still isn't found, open a new terminal so the updated PATH is picked up.
- `claude` command not found: open a new PowerShell session after running `install.ps1`. The repo profile prepends `~/.local/bin` to PATH.

## Extra Configuration

### Switching Between GPU Modes on Nvidia Optimus Systems

- [EnvyControl](https://github.com/bayasdev/envycontrol?tab=readme-ov-file#%EF%B8%8F-getting-envycontrol)

### Bluetooth

1. Install the following packages:
   ```
   bluez bluez-utils
   ```
2. Enable and start the Bluetooth service:
   ```
   systemctl enable bluetooth.service && systemctl start bluetooth.service
   ```
