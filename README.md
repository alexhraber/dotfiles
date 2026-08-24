# alexhraber/dotfiles

Opinionated macOS terminal setup for a Hyprland-shaped workflow:

- Ghostty with Tokyo Night Storm and JetBrainsMono Nerd Font
- Starship prompt
- zsh with fzf, zoxide, direnv, mise, autosuggestions, and syntax highlighting
- Herdr for persistent terminal workspaces
- Fastfetch with a compact Tokyo Night system summary
- eza, bat, ripgrep, fd, delta, Lazygit, Neovim, and btop

## Install

From this repository:

```sh
brew install fastfetch
./install.sh
exec zsh
```

The installer creates symlinks and moves any existing conflicting file to a timestamped `.backup.*` path. It intentionally does not manage shell history, completion dumps, Herdr sessions, logs, environment files, or credentials.

Fastfetch runs when an interactive terminal starts. Set `FASTFETCH_DISABLE=1` for a session when you want to skip it.

The LaunchAgent runs the local report server from `~/tailscale` on `127.0.0.1:8080` and `amp --no-tui` from `~/src` as background services under a persistent `caffeinate -s` supervisor. Ghostty can be opened separately when needed. PID files and a launch lock prevent duplicate processes. Logs are written to `/tmp/snowflake-report.log` and `/tmp/amp-no-tui.log`.
