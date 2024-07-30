# .dotfiles

## Prerequisites

- [FiraCode Nerd Font](https://www.nerdfonts.com/font-downloads)
- [`g++ 14+`](https://archlinux.org/packages/core/x86_64/gcc/)
- [Neovim v0.10.1+](https://archlinux.org/packages/extra/x86_64/neovim/)
- [`xclip`](https://archlinux.org/packages/extra/x86_64/xclip/)
- [`ripgrep`](https://archlinux.org/packages/extra/x86_64/ripgrep/)
- [`gdb 14.2+`](https://archlinux.org/packages/extra/x86_64/gdb/)
- [Node](https://github.com/nvm-sh/nvm?tab=readme-ov-file#installing-and-updating)
- [Python](https://archlinux.org/packages/core/x86_64/python/)
  - [venv](https://docs.python.org/3/library/venv.html)
- [`unzip`](https://archlinux.org/packages/extra/x86_64/unzip/)

## Getting Started

1. Clone this repo _recursively_ into your home directory:
   ```sh
   git clone --recursive git@github.com:meetinjp/.dotfiles ~/.dotfiles
   ```
2. Run the `install.sh` script:
   ```sh
   ~/.dotfiles/install.sh
   ```

## Troubleshooting

- `existing target is not owned by stow`: `unlink` or `rm` the given target and run the installation script again.
