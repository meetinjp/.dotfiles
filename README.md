# .dotfiles

## Getting Started

1. Install the prerequisites:
   ```
   git firefox stow curl neovim ripgrep wl-clipboard gcc gdb pavucontrol unzip python3 keyd brightnessctl yazi
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

### Troubleshooting

- "existing target is not owned by stow": `unlink` or `rm` the given target and run the installation script again.

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
