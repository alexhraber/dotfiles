# alexhraber/dotfiles

Opinionated macOS terminal setup for a Hyprland-shaped workflow:

- Ghostty with Tokyo Night Storm and JetBrainsMono Nerd Font
- Starship prompt
- zsh with fzf, zoxide, direnv, mise, autosuggestions, and syntax highlighting
- Herdr for persistent terminal workspaces
- AeroSpace for Option-based workspaces and keyboard-first tiling
- eza, bat, ripgrep, fd, delta, Lazygit, Neovim, and btop

## Install

From this repository:

```sh
./install.sh
exec zsh
```

The installer creates symlinks and moves any existing conflicting file to a timestamped `.backup.*` path. It intentionally does not manage shell history, completion dumps, Herdr sessions, logs, environment files, or credentials.

## Workspace keys

With AeroSpace running and allowed under System Settings → Privacy & Security → Accessibility:

- `Option+1…9` switches workspaces
- `Option+Shift+1…9` moves the focused window
- `Alt+H/J/K/L` focuses a window
- `Alt+Shift+H/J/K/L` moves a window

Ctrl is left available to terminal applications and editor workflows.
