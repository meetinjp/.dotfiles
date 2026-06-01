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

# ─── Ruby (rbenv — the "nvm for Ruby") ───────────────────────────────────────
# Apple's system Ruby is 2.6 (deprecated, below CocoaPods' 2.7.4 floor). rbenv
# installs and switches arbitrary Ruby versions per directory (driven by a
# project's .ruby-version), including legacy ones. The build deps below let
# ruby-build compile any version — old Rubies included — without hunting for
# headers. rbenv is initialised in .zshrc (`eval "$(rbenv init - zsh)"`).
brew "rbenv"                      # Ruby version manager (the nvm-for-Ruby)
brew "ruby-build"                 # rbenv backend: downloads + compiles Ruby versions
brew "rbenv-default-gems"         # auto-installs ~/.rbenv/default-gems (bundler) on every `rbenv install`
brew "openssl@3"                  # TLS for compiled Ruby (ruby-build links against it)
brew "libyaml"                    # Ruby psych/YAML ext — CocoaPods + fastlane configs need it
brew "readline"                   # line editing for compiled Ruby / irb

# ─── Mobile / React Native / iOS build toolchain ─────────────────────────────
# Build the legacy React Native app for iOS / iPad. Node is in Languages above;
# Ruby is the rbenv block above. CocoaPods is deliberately NOT a brew formula:
# brew would run it on its own Ruby, so `pod` and `bundle exec pod` resolve to
# different versions (a classic version-skew footgun). Install CocoaPods via the
# app's Gemfile instead — `bundle install` then `bundle exec pod install`. See
# the README "React Native / iOS (macOS)" section.
brew "watchman"                   # file watcher the Metro bundler relies on
brew "ccache"                     # compiler cache — large speedup on native rebuilds
brew "git-lfs"                    # large binary assets (common in RN repos)
brew "xcbeautify"                 # human-readable xcodebuild output
brew "ios-deploy"                 # deploy/run a build on a tethered iPad over USB
brew "fastlane"                   # iOS build / codesign / TestFlight automation
brew "jq"                         # JSON on the CLI (RN tooling + CI glue)
brew "gh"                         # GitHub CLI
brew "mas"                        # Mac App Store CLI
# Xcode is NOT a Homebrew package. On Apple Silicon the `xcodes` cask / App
# Store work fine; on INTEL they can deliver an arm64-only build that won't
# launch ("Bad CPU type in executable") — install the *Universal* Xcode .xip
# from developer.apple.com/download instead. See README "React Native / iOS".
cask "xcodes-app"                 # GUI to manage Xcode versions (mind the Intel caveat above)

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
# Xcode is not a Homebrew package. Command Line Tools (git, clang, make) come
# from `xcode-select --install`; the full Xcode.app is installed separately —
# the `xcodes` cask above is the easiest route (`xcodes install --latest`), or
# use the App Store / `mas`. See the README "React Native / iOS (macOS)" section.
