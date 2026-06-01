# Brewfile — macOS package manifest (the pacman-list analog). Apply with:
#   brew bundle --file=~/.dotfiles/Brewfile
# Check status: brew bundle check --file=~/.dotfiles/Brewfile
# Regenerate:   brew bundle dump --describe --force --file=~/.dotfiles/Brewfile
#
# Covers the CLI/dev stack that ports from the Linux setup. The Linux desktop
# (niri, kanshi, wlsunset, Noctalia, the Win11 KVM VM, Nvidia PRIME) has no
# macOS equivalent and is intentionally absent — see README "macOS" section.

# ─── CLI / shell ─────────────────────────────────────────────────────────────
brew "stow"                       # dotfiles symlink farm (install.sh requires it)
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "starship"                   # prompt
brew "tmux"
brew "eza"                        # ls replacement (aliases in .zshrc)
brew "bat"
brew "fd"
brew "fzf"
brew "ripgrep"
brew "coreutils"                  # gdate etc. (BSD date lacks %N)

# ─── Editor / git / signing ──────────────────────────────────────────────────
brew "neovim"
brew "git"
brew "gnupg"                      # gpg/gpgconf/gpg-agent — commit signing + SSH-over-GPG
brew "pinentry-mac"               # GUI pinentry; setup.sh auto-pins it on macOS

# ─── File manager ────────────────────────────────────────────────────────────
brew "yazi"

# ─── Languages / toolchains ──────────────────────────────────────────────────
brew "node"
brew "go"
brew "rustup"                     # then run 'rustup default stable' to populate ~/.cargo/bin
brew "pnpm"

# ─── GUI apps + font ─────────────────────────────────────────────────────────
cask "ghostty"                    # terminal (native AppKit/Metal build)
cask "firefox@developer-edition"  # FDE — install.sh links Betterfox user.js into it
cask "font-fira-code-nerd-font"   # Ghostty font (no tap needed since Homebrew 4.3)

# ─── NOT in Homebrew core — install with their own scripts (as on Linux) ──────
# These manage their own ~/ dirs and the .zshrc guards already source them:
#   nvm:  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
#   bun:  curl -fsSL https://bun.sh/install | bash        # not in homebrew-core
#   uv:   curl -LsSf https://astral.sh/uv/install.sh | sh
#
# Xcode is not a Homebrew package:
#   xcode-select --install         # Command Line Tools (git, clang, make)
#   then install full Xcode from the App Store (or via `mas` / `xcodes`).
