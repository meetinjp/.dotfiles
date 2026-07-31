# zsh — bare config (no Oh-My-Zsh), starship prompt. Cross-platform: Linux
# (CachyOS/pacman) and macOS (Homebrew). Plugins:
#   Linux: sudo pacman -S starship zsh-autosuggestions zsh-syntax-highlighting
#   macOS: brew install     starship zsh-autosuggestions zsh-syntax-highlighting

# vi mode (zsh builtin)
bindkey -v
export KEYTIMEOUT=1

# Vi-mode QoL — zsh's default vi-backward-delete-char only deletes within
# the current insert session, so backspace stops working after Esc → i.
# Rebind insert-mode editing keys to the emacs-style widgets that always work.
bindkey -M viins '^?' backward-delete-char # backspace
bindkey -M viins '^H' backward-delete-char # ctrl+h
bindkey -M viins '^W' backward-kill-word   # ctrl+w
bindkey -M viins '^U' backward-kill-line   # ctrl+u
bindkey -M viins '^A' beginning-of-line    # ctrl+a
bindkey -M viins '^E' end-of-line          # ctrl+e

# History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

# Completion
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Plugins (sourced directly; no framework). Candidate paths cover pacman
# (/usr/share/zsh/plugins) and Homebrew ($HOMEBREW_PREFIX/share, with
# /opt/homebrew and /usr/local fallbacks for Apple Silicon / Intel). The
# `[[ -r ]]` guard makes the per-OS-unused entries harmless. Order matters:
# all autosuggestions candidates precede all syntax-highlighting candidates,
# because zsh-syntax-highlighting must be sourced last per upstream docs.
for _plugin in \
	/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
	/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
	"${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
	/usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
	/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
	/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
	"${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
	/usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
	[[ -r "$_plugin" ]] && source "$_plugin"
done
unset _plugin

# Prompt
command -v starship >/dev/null && eval "$(starship init zsh)"

# Editor
export EDITOR="nvim"
export VISUAL="nvim"
export GIT_EDITOR="nvim"

# Default browser — also set as the system-wide default-web-browser via
# xdg-settings; this env var covers CLI tools that read $BROWSER (gh, man,
# etc.) instead of going through xdg-open. macOS has no such command on PATH
# and apps launch via `open`, so leave $BROWSER unset there (a multi-word
# "open -a ..." value breaks tools that exec $BROWSER as a single argv).
[[ "$OSTYPE" != darwin* ]] && export BROWSER="zen-browser"

# Aliases. eza is the ls replacement (pacman/brew); guard so the shell stays
# usable on a fresh box before `eza` is installed (e.g. new macOS pre-brew) —
# bare `ls` must not turn into "command not found: eza".
alias v="nvim ."
if command -v eza >/dev/null; then
	alias ls="eza"
	alias ll="eza -la"
	alias la="eza -a"
	alias lt="eza --tree --level=2"
else
	alias ll="ls -la"
	alias la="ls -a"
	alias lt="ls -R" # no tree view without eza; -R is the closest builtin
fi

# PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$HOME/.cargo/bin"
# Go — Debian/Ubuntu (Tuxedo OS) installs the official tarball to /usr/local/go;
# `go install` drops binaries in ~/go/bin. Guarded so it's a no-op elsewhere.
[[ -d /usr/local/go/bin ]] && export PATH="$PATH:/usr/local/go/bin"
[[ -d "$HOME/go/bin" ]] && export PATH="$PATH:$HOME/go/bin"

# Codex CLI completions. compinit is initialized above; guard keeps fresh
# machines usable until install.sh installs Codex.
command -v codex >/dev/null && eval "$(codex completion zsh)"

# Ripgrep
[[ -f "$HOME/.ripgreprc" ]] && export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# nvm
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

# pnpm — `pnpm setup` writes PNPM_HOME; its default differs by OS
# (~/.local/share/pnpm on Linux, ~/Library/pnpm on macOS). The global bin shims
# live under $PNPM_HOME/bin (confirmed via `pnpm bin -g`), so PATH needs /bin.
if [[ "$OSTYPE" == darwin* ]]; then
	export PNPM_HOME="$HOME/Library/pnpm"
else
	export PNPM_HOME="$HOME/.local/share/pnpm"
fi
case ":$PATH:" in
*":$PNPM_HOME/bin:"*) ;;
*) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac

# rbenv — Ruby version manager (used to match a project's .ruby-version, e.g.
# for a React Native app's CocoaPods/bundler toolchain). Guarded so the shell
# stays clean on hosts without rbenv. `rbenv init` puts the shims dir on PATH
# and enables per-directory auto-switching.
command -v rbenv >/dev/null && eval "$(rbenv init - zsh)"

# pyenv — Python version manager (the rbenv/nvm analog for Python; per-project
# versions via .python-version, alongside uv for pip/venv). Installer puts it
# at ~/.pyenv; PATH must be set before `pyenv init` since init relies on the
# shims dir already being resolvable.
export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init - zsh)"

# Claude Code compatibility — only export if installed. Codex needs no
# executable environment variable; it is discovered directly from PATH.
_claude_bin="$(command -v claude)"
[[ -n "$_claude_bin" ]] && export CLAUDE_CODE_EXECUTABLE="$_claude_bin"
unset _claude_bin

# SSH-over-GPG — gpg-agent acts as ssh-agent. Setup is in setup.sh:
# ~/.gnupg/gpg-agent.conf gets `enable-ssh-support`, and the auth-subkey
# keygrip is registered in ~/.gnupg/sshcontrol.
export GPG_TTY="$(tty)"
if command -v gpgconf >/dev/null; then
	export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
	gpgconf --launch gpg-agent 2>/dev/null || true
fi

# Per-host overrides (gitignored).
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# --- helper functions OMZ aliases depend on ---
function git_current_branch() { git branch --show-current 2>/dev/null; }
function git_main_branch() {
	command git rev-parse --git-dir &>/dev/null || return
	local ref
	for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,stable,master}; do
		command git show-ref -q --verify $ref && {
			echo ${ref:t}
			return 0
		}
	done
	echo master
	return 1
}

# --- git aliases (matching the OMZ git plugin) ---
alias g='git'

# status / info
alias gst='git status'
alias gss='git status --short'
alias gd='git diff'
alias gds='git diff --staged'
alias glg='git log --stat'
alias glo='git log --oneline --decorate'
alias glog='git log --oneline --decorate --graph'
alias gloga='git log --oneline --decorate --graph --all'

# add / commit
alias ga='git add'
alias gaa='git add --all'
alias gapa='git add --patch'
alias gc='git commit --verbose'
alias gcmsg='git commit --message' # <- this is "commit -m", NOT gcm
alias 'gc!'='git commit --verbose --amend'
alias 'gcn!'='git commit --verbose --no-edit --amend'

# branch
alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch --delete'
alias gbD='git branch --delete --force'

# checkout / switch
alias gco='git checkout'
alias gcb='git checkout -b'
alias gcm='git checkout $(git_main_branch)' # <- checkout main, NOT commit
alias gsw='git switch'
alias gswc='git switch --create'

# fetch / pull / push
alias gf='git fetch'
alias gfa='git fetch --all --tags --prune --jobs=10'
alias gl='git pull'
alias gpr='git pull --rebase'
alias ggp='git push'
alias 'gpf!'='git push --force'
alias gpf='git push --force-with-lease --force-if-includes'
alias gpsup='git push --set-upstream origin $(git_current_branch)'
alias gpu='git push upstream'

# merge / rebase
alias gm='git merge'
alias grb='git rebase'
alias grbi='git rebase --interactive'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'

# stash
alias gsta='git stash push'
alias gstp='git stash pop'
alias gstl='git stash list'
alias gstd='git stash drop'

# reset / restore
alias grh='git reset'
alias grhh='git reset --hard'
alias grs='git restore'
alias grst='git restore --staged' # <- staged is grst
alias grss='git restore --source' # <- grss is --source in OMZ

# remote
alias gr='git remote'
alias grv='git remote --verbose'
