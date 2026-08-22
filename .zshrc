# ~/.zshrc — calm, fast, and useful.
# The prompt is Starship; the rest is intentionally plain zsh so startup stays fast.

[[ -o interactive ]] || return

# ── Environment ──────────────────────────────────────────────────────────────
export EDITOR="${EDITOR:-nvim}"
export VISUAL="$EDITOR"
export PAGER="less -FRX"
export LESS="-R"
export HOMEBREW_NO_ENV_HINTS=1
export CLICOLOR=1

# Prefer modern tools when they are installed, but keep every config portable.
if [[ -d /opt/homebrew/share/zsh/site-functions ]]; then
  fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
fi

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
if [[ -r /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# ── Aliases ──────────────────────────────────────────────────────────────────
eza_base() {
  command eza --icons=always --classify=always --color=auto --hyperlink=auto \
    --group-directories-first --no-quotes "$@"
}

alias virc='v ~/.zshrc'
alias src='. ~/.zshrc'
alias c='clear'
alias ls='eza_base'
alias l='eza_base --all --long --header --git'
alias ll='eza_base --long --header --git'
alias la='eza_base --all --long --header --git'
alias lt='eza_base --tree --level=2'
alias cat='bat --paging=never --style=plain'
alias grep='rg'
alias top='btop'
alias v='nvim'
alias vi='nvim'
alias g='git'
alias gs='git status --short --branch'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --decorate --graph -20'
alias lg='lazygit'
alias mux='herdr'
alias h='herdr'

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

# Start or reattach to the persistent Herdr workspace from the current folder.
work() { herdr --session "${1:-main}" }

# ── Starship ─────────────────────────────────────────────────────────────────
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
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
if [[ -r /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
