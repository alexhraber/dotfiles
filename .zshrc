# ~/.zshrc — calm, fast, and useful.
# The prompt is Starship; the rest is intentionally plain zsh so startup stays fast.

[[ -n ${_DOTFILES_ZSH_LOADED:-} ]] && return
[[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/zsh/env.zsh ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/env.zsh"
[[ -o interactive ]] || return
# Re-sourcing must not register hooks or wrap widgets twice. `src` starts fresh.
typeset -g _DOTFILES_ZSH_LOADED=1
typeset -g DOTFILES_ROOT="${${(%):-%N}:A:h}"

# ── Environment ──────────────────────────────────────────────────────────────
if (( $+commands[nvim] )); then
  export EDITOR="${EDITOR:-nvim}"
else
  export EDITOR="${EDITOR:-vi}"
fi
export VISUAL="$EDITOR"
export PAGER="less -FRX"
export LESS="-R"
export HOMEBREW_NO_ENV_HINTS=1
export CLICOLOR=1

# ── History ──────────────────────────────────────────────────────────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt extended_history
setopt share_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks

# ── Shell behavior ───────────────────────────────────────────────────────────
setopt autocd
setopt interactive_comments
setopt no_beep
setopt complete_in_word
setopt auto_pushd
setopt pushd_ignore_dups
setopt pushd_silent

# ── Completion ───────────────────────────────────────────────────────────────
autoload -Uz compinit
zmodload -i zsh/complist
compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' rehash true
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:messages' format '%F{yellow}%d%f'

# ── Key bindings ─────────────────────────────────────────────────────────────
bindkey -e

# ── Fuzzy finding ────────────────────────────────────────────────────────────
export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border=rounded --info=inline --prompt="❯ " --pointer="▶" --marker="┃"'
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --color=bg+:#3b4261,fg:#c0caf5,fg+:#c0caf5,hl:#7dcfff,hl+:#7dcfff,border:#565f89,prompt:#7aa2f7,pointer:#bb9af7,marker:#9ece6a,spinner:#e0af68,header:#565f89"
[[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/zsh/theme.zsh ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/theme.zsh"
if (( $+commands[bat] )); then
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {}' --preview-window=right:55%:wrap --bind='ctrl-/:toggle-preview'"
fi
if (( $+commands[eza] )); then
  export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always --icons=always {}' --preview-window=right:55% --bind='ctrl-/:toggle-preview'"
fi
if (( $+commands[fd] )); then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
if (( $+commands[fzf] )) && [[ -t 0 && -t 1 ]]; then
  source <(fzf --zsh)
fi

# ── Smarter navigation and project tooling ───────────────────────────────────
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

# Low-noise interactive feedback: suggestions from history and command highlighting.
typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#565f89'
typeset -ga ZSH_AUTOSUGGEST_STRATEGY=(history completion)
if [[ -r ${HOMEBREW_PREFIX:-}/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# ── Aliases ──────────────────────────────────────────────────────────────────
eza_base() {
  command eza --icons=always --classify=always --color=auto --hyperlink=auto \
    --group-directories-first --no-quotes "$@"
}

alias virc='v ~/.zshrc'
alias src='exec zsh -l'
alias c='clear'
if (( $+commands[eza] )); then
  alias ls='eza_base'
  alias l='eza_base --all --long --header --git'
  alias ll='eza_base --long --header --git'
  alias la='eza_base --all --long --header --git'
  alias lt='eza_base --tree --level=2'
else
  alias l='ls -lah' ll='ls -lh' la='ls -lah'
fi
(( $+commands[bat] )) && alias cat='bat --paging=never --style=plain'
# Keep grep's standard flags and semantics; use rg explicitly.
(( $+commands[btop] )) && alias top='btop'
if (( $+commands[nvim] )); then
  alias v='nvim' vi='nvim'
else
  alias v='vi'
fi
alias g='git'
alias gs='git status --short --branch'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --decorate --graph -20'
(( $+commands[lazygit] )) && alias lg='lazygit'
(( $+commands[tmux] )) && alias tm='tmux new-session -A -s main'
alias dotfiles='"${DOTFILES_ROOT:-$HOME/src/dotfiles}/scripts/dotfiles"'

# Jump up without thinking about how many ../'s you need.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ── Small functions ──────────────────────────────────────────────────────────
mkcd() { mkdir -p -- "$1" && cd -- "$1" }
take() { mkcd "$1" }
extract() {
  [[ -f "$1" ]] || { print -u2 "extract: file not found: $1"; return 1; }
  case "$1" in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;
    *.tar.gz|*.tgz)   tar xzf "$1" ;;
    *.tar.xz|*.txz)   tar xJf "$1" ;;
    *.tar)            tar xf "$1" ;;
    *.zip)            unzip "$1" ;;
    *.gz)             gunzip "$1" ;;
    *.bz2)            bunzip2 "$1" ;;
    *.xz)             unxz "$1" ;;
    *.7z)             7z x "$1" ;;
    *) print -u2 "extract: unsupported archive: $1"; return 1 ;;
  esac
}

[[ -r "$XDG_CONFIG_HOME/zsh/projects.zsh" ]] && source "$XDG_CONFIG_HOME/zsh/projects.zsh"
[[ -r "$XDG_CONFIG_HOME/zsh/local-models.zsh" ]] && source "$XDG_CONFIG_HOME/zsh/local-models.zsh"
[[ -r "$XDG_CONFIG_HOME/zsh/workspaces.zsh" ]] && source "$XDG_CONFIG_HOME/zsh/workspaces.zsh"

# ── Starship ─────────────────────────────────────────────────────────────────
# Machine-specific additions stay outside Git and before the widget wrappers.
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
if (( $+commands[starship] )) && [[ ${TERM:-dumb} != dumb ]]; then
  eval "$(starship init zsh)"
fi

# Show a small system summary when an interactive terminal starts.
if (( $+commands[fastfetch] )) && [[ -o login && -t 1 && -z "${FASTFETCH_DISABLE:-}" ]]; then
  fastfetch
fi

# Keep this last: syntax highlighting wraps the final line editor widgets.
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#bb9af7'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[function]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[path]='fg=#9ece6a,underline'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#e0af68'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#f7768e'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#e0af68'
if [[ -r ${HOMEBREW_PREFIX:-}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
