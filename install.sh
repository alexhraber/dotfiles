#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

link_file() {
  local target="$1"
  local relative_source="$2"
  local source="$repo_root/$relative_source"

  mkdir -p -- "$(dirname -- "$target")"

  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    return
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local backup="$target.backup.$(date +%Y%m%d-%H%M%S)"
    mv -- "$target" "$backup"
    printf 'Backed up %s -> %s\n' "$target" "$backup"
  fi

  ln -s -- "$source" "$target"
  printf 'Linked %s -> %s\n' "$target" "$source"
}

link_file "$HOME/.zprofile" ".zprofile"
link_file "$HOME/.zshrc" ".zshrc"
link_file "$HOME/.gitconfig" ".gitconfig"
link_file "$HOME/.aerospace.toml" ".aerospace.toml"
link_file "$HOME/.config/starship.toml" ".config/starship.toml"
link_file "$HOME/.config/ghostty/config" ".config/ghostty/config"
link_file "$HOME/.config/herdr/config.toml" ".config/herdr/config.toml"

printf '\nDotfiles linked from %s\n' "$repo_root"
