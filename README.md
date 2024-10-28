# .dotfiles

## Getting Started

1. Install the prerequisites:
   ```
   git \
   firefox \
   stow \
   curl \
   neovim ripgrep xclip gcc gdb \
   pavucontrol \
   unzip \
   python3 python3-venv \
   xorg-xmodmap
   ```
   - [nvm](https://github.com/nvm-sh/nvm?tab=readme-ov-file#installing-and-updating)
1. Clone this repo _recursively_ into your home directory:
   ```
   git clone --recursive git@github.com:meetinjp/.dotfiles ~/.dotfiles
   ```
1. Run the `install.sh` script:
   ```
   ~/.dotfiles/install.sh
   ```
1. Install the postrequisites:
   ```
   zsh \
   neovim
   ```
   - [FiraCode Nerd Font](https://www.nerdfonts.com/font-downloads)
   - [Alacritty](https://github.com/alacritty/alacritty/blob/master/INSTALL.md)
   - [Oh My Zsh](https://ohmyz.sh/#install)
   - [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md#oh-my-zsh)

### Troubleshooting

- "existing target is not owned by stow": `unlink` or `rm` the given target and run the installation script again.

## Extra Configuration

### Touchpad Synaptics

```ini
xf86-input-libinput

# /usr/share/X11/xorg.conf.d/40-libinput.conf
Option "Tapping" "on"
Option "NaturalScrolling" "true"
```

### Switching Between GPU Modes on Nvidia Optimus Systems

```
envycontrol

envycontrol -s integrated
```

### Bluetooth

```
bluez bluez-utils

systemctl enable bluetooth.service && systemctl start bluetooth.service
```

### Git

```
git config --global user.email "meetinjp@proton.me"
git config --global user.name "meetinjp"
```

## TODOs

- [ ] [Backlight](https://wiki.archlinux.org/title/Backlight) (currently using `light`)
