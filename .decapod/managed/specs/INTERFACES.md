# Interfaces

## CLI

install.sh accepts --groups terminal,git,codex,workspace, --all, --deps and
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

## Shell and editor

proj chooses directories under PROJECTS_DIR (default ~/src). wt selects
worktrees; wtnew takes a new branch and explicit directory. Paths with spaces
are supported. mlx/mlxchat/mlxserve use MLX_ENV or ~/.venvs/mlx; cxlocal uses
CODEX_LOCAL_MODEL or the installed qwen3-coder:30b model through Ollama.
Neovim's leader is Space; mappings and local.lua extension are documented in
README.md. Codex profiles use separate top-level TOML files.

## External dependencies

Homebrew, GitHub Git transport, rustup/Cargo, Ollama, MLX and Podman remain
independently managed. Native Neovim package installation fetches pinned plugin
commits on first startup. No service, REST API or event protocol is authored by
this repository.

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `6fba237828fbded719d7d827b3c1a53e8a4cf4a6874d4d4993811e935e34eac4`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (1 files), `tests/` (1 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
