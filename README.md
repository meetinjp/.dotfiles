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

1. Install the prerequisites (e.g. via `winget`):
   - `Git.Git`
   - `Neovim.Neovim`
   - `BurntSushi.ripgrep.MSVC`
1. Clone this repo _recursively_ into your home directory:
   ```
   git clone --recursive git@github.com:meetinjp/.dotfiles $HOME\.dotfiles
   ```
1. Run the `install.ps1` script in PowerShell:
   ```
   powershell -ExecutionPolicy Bypass -File $HOME\.dotfiles\install.ps1
   ```
   (or `pwsh` for PowerShell 7+). It creates directory junctions and stubs `$PROFILE` — no admin or Developer Mode required.
1. Run the `setup.ps1` script from an **elevated** PowerShell for one-shot machine tweaks (e.g. Caps Lock → Ctrl remap):
   ```
   powershell -ExecutionPolicy Bypass -File $HOME\.dotfiles\setup.ps1
   ```
1. Run the `setup.sh` script from Git Bash to configure Git:
   ```
   ~/.dotfiles/setup.sh
   ```

#### Troubleshooting

- "Target exists and is not a link": move or remove the offending path (e.g. `%LOCALAPPDATA%\nvim`) and rerun `install.ps1`.
- Profile stub not loaded: confirm which host you're in by checking `$PROFILE`, then rerun `install.ps1` from that host.

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
