# Interfaces

## CLI

install.sh accepts --groups with any comma-separated subset of terminal, git,
codex, workspace, dev, infra, ai, apps and macos, plus --all, --deps and
--dry-run. The default group is terminal. scripts/dotfiles doctor uses the same
group selection. Restore accepts a manifest via scripts/dotfiles restore or
install.sh --restore; dry-run previews both operations.

Git signing requires the git group, --git-name, --git-email and --signing-key
pointing to an existing public SSH key. No private key is copied. Invalid
arguments, directory conflicts, failed subprocesses and failed filesystem
operations return nonzero with diagnostics.

## Backup manifest

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
cws takes an explicit container image and optional command, mounts only the
current project, and requires an already-running Podman engine. It never starts
a VM. tm attaches or creates the main tmux session with the standard prefix.
Neovim's leader is Space; mappings and local.lua extension are documented in
README.md. Codex profiles use separate top-level TOML files.

The root justfile exposes preview, install, check, doctor, editor-check,
brew-check and outdated. scripts/editor_check.py validates installed language
servers in disposable fixtures rather than changing project files.

## External dependencies

Homebrew, GitHub Git transport, rustup/Cargo, Ollama, MLX and Podman remain
independently managed. Native Neovim package installation fetches pinned plugin
commits on first startup. No service, REST API or event protocol is authored by
this repository.

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `bd87ea8ea1effbcd9214006f360947918b918f94b45b80ee867599d5e1d77e51`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (3 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
