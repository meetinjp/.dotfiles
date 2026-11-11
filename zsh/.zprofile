# Login-shell PATH for terminal and display-manager sessions.

# Homebrew (macOS / Linuxbrew). Put brew + its tools on PATH for login shells;
# `brew shellenv` also exports HOMEBREW_PREFIX, which .zshrc uses to locate the
# zsh plugins. Probes each known prefix — Apple Silicon, Intel, Linuxbrew — and
# the first that exists wins. No-op on hosts without Homebrew (for example, Ubuntu).
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [[ -x "$_brew" ]] && eval "$("$_brew" shellenv)" && break
done
unset _brew

# Put user bin dirs on PATH for LOGIN shells, not just interactive (.zshrc) ones.
# The niri session is launched by a login, non-interactive shell (niri-session →
# `exec -l "$SHELL"` / `exec niri --session`), which sources THIS file but never
# .zshrc — so without this, GUI apps niri spawns that live under ~/.local/bin
# (e.g. `zen-browser`) or ~/.cargo/bin are not found and silently fail to start.
# Idempotent; rustup's ~/.zshenv already adds ~/.cargo/bin, we just guarantee it.
for _d in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    case ":$PATH:" in *":$_d:"*) ;; *) [[ -d "$_d" ]] && PATH="$_d:$PATH" ;; esac
done
unset _d
export PATH
