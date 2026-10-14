# Shared by login and non-login interactive shells. Keep this free of plugins.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
[[ -r "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
if [[ -z ${HOMEBREW_PREFIX:-} ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    export HOMEBREW_PREFIX=/opt/homebrew
  elif [[ -x /usr/local/bin/brew ]]; then
    export HOMEBREW_PREFIX=/usr/local
  elif (( $+commands[brew] )); then
    export HOMEBREW_PREFIX="$(command brew --prefix)"
  fi
fi
typeset -U path fpath
path=("$HOME/.local/bin" ${HOMEBREW_PREFIX:+"$HOMEBREW_PREFIX/bin"} ${HOMEBREW_PREFIX:+"$HOMEBREW_PREFIX/sbin"} $path)
if [[ -d ${HOMEBREW_PREFIX:-}/share/zsh/site-functions ]]; then
  fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
fi
export PATH
