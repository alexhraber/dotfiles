# Architecture

## System boundary

This is a configuration repository, not a service. Bash entrypoints dispatch
to the Python standard-library installer. zsh and Lua configure the user's
shell and editor; Homebrew manages the curated tool dependencies.

## Components and data flow

- install.sh -> scripts/dotfiles -> scripts/manage.py: parse group selection,
  construct operations, preflight destinations, snapshot original files,
  replace each file atomically and emit a backup manifest.
- scripts/manage.py apply(): backs up all changed destinations before applying
  operations; on an application error it restores already completed operations.
  There is no cross-file filesystem transaction or crash-atomicity claim.
- restore(): validates every current destination and backup before restoration,
  refusing to overwrite subsequent edits.
- .config/zsh/env.zsh: Homebrew/local/Cargo PATH setup, shared by login and
  interactive shells. .zshrc registers hooks once and loads navigation and
  explicit local-model helpers.
- .config/nvim/init.lua: native vim.pack with pinned Tokyo Night and mini.nvim;
  Rust LSP uses the existing rust-analyzer executable.
- .gitconfig: portable settings included by the existing user configuration;
  local identity and signing overrides remain in ~/.gitconfig.local.
- .codex: allowlisted portable files copied into Codex home to keep app-written
  account and runtime settings outside Git.

## State and failures

Configuration backups use private local state directories and JSON manifests.
Neovim plugin checkouts, bat caches, shell history, Codex state and Podman VM
files are runtime state, not versioned configuration. Package installation,
plugin downloads and repository updates are outside configuration restoration.
The installer assumes a single writer; it detects destination changes during
installation but does not coordinate simultaneous independent installers.

## Isolation

Decapod uses a claimed task and isolated workspace. Container policy is
configured with Podman as the intended runtime; all VM starts must be headless.
The installed Decapod full-readiness adapter currently targets Decapod's own
source/CI contract, so generic dotfiles readiness remains unsupported.

<!-- decapod:capability-overlay:persistent-state:start -->

Generated capability obligations: `persistent-state` is declared for this project. These are decisions and proof requirements, not claims of implemented behavior. Resolve each against project source and tests; record unsupported or non-applicable mechanisms explicitly.

## Persistent State Architecture Overlay

### State Ownership
- Each entity type MUST have a designated state owner
- State ownership boundaries MUST be explicitly documented
- Cross-boundary state access MUST go through defined interfaces

### Transaction Boundaries
- Multi-entity mutation atomicity and partial-failure treatment MUST be documented and proven for the selected store
- Transaction boundaries MUST be documented in ARCHITECTURE.md
- Document compensation or other partial-failure treatment if distributed operations exist

### Storage Abstraction
- Storage ownership, consistency behavior, and access boundaries MUST be explicit
- Portability or swappable implementations are project decisions, not universal requirements
- Migration and rollback treatment MUST match the selected storage technology
<!-- decapod:capability-overlay:persistent-state:end -->

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `6fba237828fbded719d7d827b3c1a53e8a4cf4a6874d4d4993811e935e34eac4`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (1 files), `tests/` (1 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
