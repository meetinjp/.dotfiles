# macOS configuration

The shared CLI configuration and Ghostty settings have a macOS profile.
Desktop services remain Linux-only. This cleanup has not been tested on a Mac.

Install Command Line Tools and Homebrew through their official installers, then:

```sh
brew bundle --file=Brewfile
git submodule update --init nvim/.config/nvim
./install.sh --profile macos --dry-run
./install.sh --profile macos
```

The installer adds Ghostty's platform override to its Application Support
configuration. Unlinking Ghostty removes only that managed include and preserves
unrelated settings.

Ruby configuration is included for rbenv. Match the project's `.ruby-version`
and install gems from its Gemfile. Mobile build tools have a separate manifest:

```sh
brew bundle --file=macos/Brewfile.mobile
```

Project-specific Xcode, signing, and React Native instructions belong in the
application repository. Per-project runtime versions remain project-owned.
Git identity and key setup are separate: `./setup.sh git` and `./setup.sh keys`.
