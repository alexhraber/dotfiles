# Project and worktree navigation; all paths are passed as arguments.
proj() {
  local root="${PROJECTS_DIR:-$HOME/src}" selected
  (( $+commands[fzf] )) || { print -u2 'proj: install fzf'; return 1; }
  [[ -d $root ]] || { print -u2 "proj: directory missing: $root"; return 1; }
  selected=$(printf '%s\n' "$root"/*(N/) | command fzf --prompt='Project ❯ ' \
    --preview='git -C {} status --short --branch 2>/dev/null; ls -la {}' \
    --preview-window=right:50%) || return
  [[ -n $selected ]] && builtin cd -- "$selected"
}

wt() {
  local selected
  (( $+commands[fzf] )) || { print -u2 'wt: install fzf'; return 1; }
  command git rev-parse --git-dir >/dev/null 2>&1 || return
  selected=$(command git worktree list --porcelain | \
    command sed -n 's/^worktree //p' | command fzf --prompt='Worktree ❯ ' \
    --preview='git -C {} status --short --branch 2>/dev/null') || return
  [[ -n $selected ]] && builtin cd -- "$selected"
}

# Explicit destination avoids guessing branch names or overwriting a worktree.
wtnew() {
  (( $# == 2 )) || { print -u2 'usage: wtnew <new-branch> <directory>'; return 2; }
  command git worktree add -b "$1" -- "$2" && builtin cd -- "$2"
}
