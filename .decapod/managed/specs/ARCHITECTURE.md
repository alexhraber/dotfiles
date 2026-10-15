# Architecture

## Direction

This is a configuration repository, not a service. Bash entrypoints dispatch
to the Python standard-library installer. zsh and Lua configure the user's
shell and editor; Homebrew manages the curated tool dependencies.

## Current Facts

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
  Installed servers cover Rust, Python, JS/TS, Lua, Bash and TOML. Python uses
  project virtual environments and Ruff formatting.
- The same pinned mini.nvim package supplies the workbench, tabline and static
  indent guide; no additional editor plugin or runtime is introduced. Starship
  and fzf share the theme palette; tmux styling uses built-in formats and keys.
- scripts/macos_preferences.py preserves floating-point values as well as
  integers, strings and booleans, including fractional preexisting Dock sizes.
- scripts/macos_preferences.py: reads typed defaults, snapshots changed keys,
  applies with per-key readback and rolls back on error. Preferences and files
  are separate transactions; restoration refuses later edits.
- .config/zsh/workspaces.zsh: explicit project-only Podman invocation. It checks
  a running engine but never creates or starts a VM. Host credentials and engine
  sockets are not mounted; source remains writable and SELinux labels are
  disabled for shared macOS filesystems. Live container integration is checked
  separately from the portable fake-engine argument tests.
- Brewfile: scoped direct dependencies including dev, infrastructure, local AI
  and Chrome. Installed unmanaged Chrome remains externally managed.
- Homebrew Bundle receives group selection through HOMEBREW_DOTFILES_GROUPS;
  its preserved namespace is required because Bundle drops an unprefixed custom
  variable. The dev group copies mise configuration, independent of a worktree.
- The reverse group copies zsh/reverse.zsh and adds one source line to the
  existing .zshrc.local through the ordinary backed-up file operations. It
  discovers Homebrew Ghidra/JDK only when explicit environment values are absent.
- scripts/setup-xcode runs in a visible local terminal. mas and sudo own their
  authentication prompts; Apple presents its license before first-launch setup
  and explicit iOS platform download. This is outside the regular installer.
- requirements/mlx.in and its compiled requirements/mlx.txt pin a separate
  Python 3.12 Apple-silicon inference stack. Environment preparation and the
  verified stable-link switch are explicit machine operations, not login hooks.
- .gitconfig: portable settings included by the existing user configuration;
  local identity and signing overrides remain in ~/.gitconfig.local.
- .codex: allowlisted portable files copied into Codex home to keep app-written
  account and runtime settings outside Git.

## Data and Contracts

Configuration backups use private local state directories and JSON manifests.
Neovim plugin checkouts, bat caches, shell history, Codex state and Podman VM
files are runtime state, not versioned configuration. Package installation,
plugin downloads and repository updates are outside configuration restoration.
The installer assumes a single writer; it detects destination changes during
installation but does not coordinate simultaneous independent installers.

## Concurrency and Runtime Model

Decapod uses a claimed task and isolated workspace. Container policy is
configured with Podman as the intended runtime; all VM starts must be headless.
Repository proof uses Decapod's supported repository-local profile with reviewed
commands and toolchain declarations. Hosted CI execution is a separate result.

## Topology

```text
Brewfile -> Homebrew tools
install.sh -> scripts/dotfiles -> scripts/manage.py -> installed config
                                      |                  |
                                      v                  v
                                private backups    shell/editor/apps
scripts/check -> scripts/check.py -> ShellCheck + zsh parser + unittest
```

## Execution Path

The installer selects groups, validates all targets and snapshots changes before
atomic per-file replacement. macOS preferences use a separate typed transaction.
Restoration preflights every target and backup before replacing any destination.

## Deployment Topology

The product installs into a local user account. Portable configuration is linked
or copied from a retained checkout; packages and mutable runtime stores are
external. The verification image installs Python, zsh and ShellCheck without
starting a graphical VM interface or mounting host credentials.

## Delivery Plan

Review changes against the accepted base, checkpoint the candidate, run configured
repository proof and inspect platform-specific host checks. Publish only with
task authorization and passing readiness; GitHub's platform matrix remains
separate execution evidence. Reapply a reviewed retained checkout to switch links.

## Risks and Mitigations

Symlinks depend on retaining their source checkout; private backups preserve old
links and resolved content. Package/model installation is not rolled back with
configuration. Concurrent installers are unsupported; destination readback catches
some races. Explicit invocations keep expensive models and VMs out of shell login.

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

- Repository signal fingerprint: `60748b35822094592834a86196c34c2bfa40d4d9855ae3240bf34f0c4016250a`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (4 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
