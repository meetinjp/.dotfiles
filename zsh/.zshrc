# zsh — bare config (no Oh-My-Zsh), starship prompt.
# Plugins installed via pacman:
#   sudo pacman -S starship zsh-autosuggestions zsh-syntax-highlighting

# vi mode (zsh builtin)
bindkey -v
export KEYTIMEOUT=1

# Vi-mode QoL — zsh's default vi-backward-delete-char only deletes within
# the current insert session, so backspace stops working after Esc → i.
# Rebind insert-mode editing keys to the emacs-style widgets that always work.
bindkey -M viins '^?' backward-delete-char    # backspace
bindkey -M viins '^H' backward-delete-char    # ctrl+h
bindkey -M viins '^W' backward-kill-word      # ctrl+w
bindkey -M viins '^U' backward-kill-line      # ctrl+u
bindkey -M viins '^A' beginning-of-line       # ctrl+a
bindkey -M viins '^E' end-of-line             # ctrl+e

# History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

# Completion
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Plugins (sourced directly; no framework).
# zsh-syntax-highlighting must come last per upstream docs.
for _plugin in \
    /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
    /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
do
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
# etc.) instead of going through xdg-open.
export BROWSER="firefox-developer-edition"

# Aliases
alias v="nvim ."
alias ls="eza"
alias ll="eza -la"
alias la="eza -a"
alias lt="eza --tree --level=2"

# PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$HOME/.cargo/bin"

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

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Claude Code binary — only export if installed.
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

# pnpm
export PNPM_HOME="/home/meetinjp/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end
