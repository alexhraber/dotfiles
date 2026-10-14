# alexhraber/dotfiles

A reproducible macOS terminal and editor setup: Ghostty, Tokyo Night Storm,
JetBrainsMono Nerd Font, Starship, zsh, Neovim, Git, and Codex. Decapod manages
agent work in isolated Podman container workspaces.

## Install

Homebrew and Python 3 are needed to bootstrap. The dependency installer adds
Python 3.14 for configuration validation. Inspect `Brewfile` and `install.sh`
before applying a new checkout.

```sh
./install.sh --dry-run --deps       # Preview the default terminal group
./install.sh --deps                 # Install tools and terminal/editor config
./install.sh --all --deps           # Include Git, Codex, and workspace tools
exec zsh -l
```

Groups are `terminal`, `git`, `codex`, and `workspace`. Select any combination
with `--groups terminal,git`. Dependency installation uses a curated Brewfile
and `--no-upgrade`; it does not remove unrelated packages. Podman is installed
by the workspace group. Rust and Decapod remain managed by your existing rustup
and Cargo installation.

The installer validates destinations before changing files, saves every
conflicting file or symlink in a private backup directory, and writes a JSON
manifest. Repeated installs make no configuration changes when files already
match. Ghostty's XDG and macOS application-support config locations are both
managed so they cannot accidentally disagree. No LaunchAgents or background
application services are installed.

Backups default to `~/.local/state/dotfiles/backups/`; the exact manifest path
is printed after installation. Restore configuration with:

```sh
./install.sh --restore /path/to/manifest.json --dry-run
./install.sh --restore /path/to/manifest.json
```

Restore checks all targets and backups first and refuses to overwrite later
edits. It restores original symlinks as symlinks; `.resolved-content` files also
preserve their original contents. Restoration does not undo repository updates,
package installations, plugin downloads, or runtime caches. Existing directories
are never replaced. `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, and `CODEX_HOME` are
respected when set.

## Shell and projects

Login and non-login interactive zsh share `.config/zsh/env.zsh`. It detects the
Homebrew prefix, adds local tools, and sources `~/.cargo/env` when available.
Mise can put its project shims ahead of these paths. Plugins are registered once
per shell; `src` starts a fresh login shell to reload changes. Optional local
settings go in `~/.zshrc.local` and remain outside Git.

- `proj`: fuzzy-pick a directory under `~/src` (override with `PROJECTS_DIR`).
- `wt`: fuzzy-pick a Git worktree of the current repository.
- `wtnew <new-branch> <directory>`: create a worktree and enter it.
- `v`, `vi`: Neovim when installed, with a system-editor fallback.
- `lg`: Lazygit; `gs`, `gd`, `gds`, `gl`: common Git views.
- `dotfiles doctor --all`: inspect the installed configuration and dependencies.

Modern command aliases are enabled only when their tools exist. `grep` keeps its
standard behavior; invoke `rg` directly. Fastfetch runs in interactive login
terminals; set `FASTFETCH_DISABLE=1` to skip it. Ghostty retains its standard
split, tab, zoom, and reload shortcuts.

## Neovim

The configuration requires Neovim 0.12+. Native `vim.pack` installs two plugins
from HTTPS on first startup: Tokyo Night and mini.nvim. Both are pinned to
specific commits in `.config/nvim/init.lua`. No additional language runtimes
are installed when opening files. Plugin checkouts and the generated package
lockfile stay in Neovim's local directories.

Use Space as the leader:

| Keys | Action |
| --- | --- |
| Space ff / fg / fb / fh | Find files, live text search, buffers, help |
| Space e | File explorer |
| Space gs | Pick Git hunks |
| Space w / q | Save / open quickfix |
| Ctrl h / j / k / l | Move between splits |
| gd / gr / K | Definition, references, hover with an attached language server |
| Space rn / ca / cf | Rename, code action, format with an attached server |

Persistent undo, completion, surrounding pairs, Git diff signs, and a statusline
are enabled. Rust LSP uses `rust-analyzer` from the existing Rust toolchain;
install that component with `rustup component add rust-analyzer`. Optional
language-server configuration and local settings belong in
`~/.config/nvim/local.lua` (or the equivalent XDG path).

Tokyo Night Storm is shared by Ghostty, Neovim, Starship, bat, delta, and Lazygit.
The installer builds bat's theme cache. Its vendored theme is attributed and
licensed in `.config/bat/themes/NOTICE` and `LICENSE`.

## Git and signing

The Git group adds an include to your existing `~/.gitconfig`, preserving
identity, credential helpers, and other settings. Portable behavior lives in
`.gitconfig`; machine-specific overrides live in `~/.gitconfig.local`.

Configure an identity and SSH signing explicitly, using a **public** key:

```sh
./install.sh --groups git \
  --git-name 'Your Name' \
  --git-email 'your-email@example.com' \
  --signing-key "$HOME/.ssh/id_ed25519_github.pub"
```

The local signing configuration and allowed-signers file are backed up before
changes. Key material is never copied into this repository. The matching private
key must be available locally or through an SSH agent, and GitHub needs the
public key registered for signing as well as authentication.

## Codex

Only portable preferences, concise global instructions, and CLI profile files
are tracked. Installation copies them to Codex home with mode 0600, so app edits
cannot write credentials or machine settings back into the repository. A later
explicit Codex reinstall backs up local changes and reapplies the tracked files.
Authentication, sessions, databases, caches, downloaded plugins, and accumulated
approval rules remain local.

```sh
codex                         # Existing model preference, high effort
codex --profile quick         # Medium effort
codex --profile deep-review   # Extra-high effort
```

Profile files use top-level keys, following the current
[Codex profile format](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles).
Global `AGENTS.md` contains working preferences; repository instructions remain
specific to each project. Approval and sandbox boundaries are preserved.

## Existing local models

`cxlocal` starts Codex explicitly with Ollama and the already-installed
`qwen3-coder:30b` model. Set `CODEX_LOCAL_MODEL` to choose another local model.
It preserves approval and sandbox settings; ordinary `codex` keeps the cloud
model preference. Ollama's service and model files remain locally managed.

`mlx`, `mlxchat`, and `mlxserve` use the existing `~/.venvs/mlx` environment
without changing the shell's Python. Override its location with `MLX_ENV`.
`mlxserve` binds to loopback unless explicitly overridden. These commands do
not run during shell startup or automatically download models.

## Podman and Decapod

On macOS, Podman runs containers inside a Linux VM. The installer installs the
CLI; VM creation and startup are explicit operations:

```sh
podman machine list
podman machine init --cpus=4 --memory=4096 --disk-size=100 dotfiles
podman machine start --quiet --no-info dotfiles
podman info
```

Use an existing machine when one is already configured. VM disks, SSH keys,
connections, sessions, and container state remain local. No login service is
installed. Start the VM before using container workspaces. All VM starts must be headless;
do not enable Podman debug logging on macOS, since it adds the vfkit GUI.

This repository is initialized with Decapod's local backend and container
isolation. Follow `AGENTS.md` and `decapod docs ingest` for its session, task,
workspace, and validation lifecycle. Podman is the intended local runtime.
The authored specifications under `.decapod/managed/specs/` describe this
repository; runtime state is ignored. Decapod initialization by itself does not
prove that repository checks or publication readiness passed. Decapod 0.111.1
currently has a full-readiness adapter specific to its own Rust repository;
this dotfiles CI contract is unsupported. Keep that limitation separate from
the actual scripts/check and local configuration results. VM startup
troubleshooting is deferred; see [the upstream headless-startup issue](https://github.com/DecapodLabs/decapod/issues/1417).

## Verification

```sh
scripts/check                  # ShellCheck, zsh syntax, and isolated tests
scripts/dotfiles doctor --all   # Dependencies and installed configuration
```

The tests exercise scoped installation, backups, rollback on failure, repeated
installation, restoration, refusal to overwrite later edits, preservation of Git
identity and Codex state, worktree paths with spaces, and shell hook behavior.
GitHub Actions runs the same suite on Linux and macOS. Config and package checks
on the actual Mac are separate from the portable test suite.
