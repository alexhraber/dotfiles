# Interfaces

## Inbound Contracts

install.sh accepts --groups with any comma-separated subset of terminal, git,
codex, workspace, dev, reverse, apple, infra, ai, apps and macos, plus --all, --deps and
--dry-run. The default group is terminal. scripts/dotfiles doctor uses the same
group selection. Restore accepts a manifest via scripts/dotfiles restore or
install.sh --restore; dry-run previews both operations.

Git signing requires the git group, --git-name, --git-email and --signing-key
pointing to an existing public SSH key. No private key is copied. Invalid
arguments, directory conflicts, failed subprocesses and failed filesystem
operations return nonzero with diagnostics.

## Data Ownership

Version 1 contains repository and changes. Each operation records target,
original state, installed state and a backup path when the original existed.
States are absent, symlink with link value, or file with SHA-256 and mode.
Resolved symlink contents are also retained for inspection. Restore verifies
backup state and rejects current contents differing from both original and
installed states. The manifest is local and should be treated as trusted input.

macOS preference manifests have version 1 and kind macos-preferences, with
domain/key changes containing typed original and installed values. An absent
original key is null. The same restore CLI dispatches to per-key restoration
on macOS and rejects later edits before writing any preferences. Configuration
files and preferences use separate manifests and application transactions.

## Shell and editor

proj chooses directories under PROJECTS_DIR (default ~/src). wt selects
worktrees; wtnew takes a new branch and explicit directory. Paths with spaces
are supported. mlx/mlxchat/mlxserve use MLX_ENV or ~/.venvs/mlx; cxlocal uses
CODEX_LOCAL_MODEL or the installed qwen3-coder:30b model through Ollama.
aiup explicitly starts Ollama in the foreground with no model preload and a
zero keep-alive default, Flash Attention enabled, and q8_0 KV cache. Ctrl-C in
that terminal stops the server. No helper registers a login service; clients
may override keep_alive per request. Existing background services must be
stopped separately with brew services stop ollama.
cws takes an explicit container image and optional command, mounts only the
current project, and requires an already-running Podman engine. It never starts
a VM. tm attaches or creates the main tmux session with the standard prefix.
Neovim's leader is Space; mappings and local.lua extension are documented in
README.md. Codex profiles use separate top-level TOML files.

Ctrl-T previews files with bat, Alt-C previews directories with eza, and Ctrl-/
toggles previews. Tmux retains Ctrl-b: h/j/k/l select panes, Shift-h/j/k/l resize,
Tab switches to the previous window. Neovim Space ss opens the workbench;
[b and ]b switch buffers. The default theme is Tokyo Night Storm throughout.

Routine workflows invoke install.sh, scripts/check, scripts/dotfiles doctor,
scripts/editor_check.py and Homebrew directly. No Just task runner or wrapper
is required. scripts/editor_check.py validates installed language servers in
disposable fixtures rather than changing project files.

The dev group copies .config/mise/config.toml; mise install explicitly installs
the declared Node/npm defaults. The reverse group copies zsh/reverse.zsh and
adds its source to .zshrc.local, retaining other settings and explicit Java/Ghidra
choices. The apple group installs mas on macOS; scripts/setup-xcode requires a
visible local terminal and installs Xcode, selects it, presents Apple's license,
runs first-launch setup and downloads iOS. Signing uses local Xcode account
assets and command-line build overrides; no team or signing identity is tracked.

## Outbound Dependencies

Homebrew, GitHub Git transport, rustup/Cargo, Ollama, MLX and Podman remain
independently managed. Native Neovim package installation fetches pinned plugin
commits on first startup. No service, REST API or event protocol is authored by
this repository.

## Failure Semantics

Invalid arguments, unsupported preference types, directory conflicts and failed
subprocesses return nonzero. File application restores completed replacements on
a caught failure; preferences have a separate rollback. Restore rejects changed
backups or later user edits before mutating any destination. Process interruption
can leave partial state; the backup manifest remains the recovery input.

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `565a71c979f06f17c41ba3d6b7655fe0f259bb145c4a7d039d23c4ea656feca1`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (4 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
