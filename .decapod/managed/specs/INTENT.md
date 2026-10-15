# Intent

## Product Outcome

Provide a repeatable macOS terminal and development environment for Alex:
Ghostty with Tokyo Night Storm and Nerd Font, zsh navigation and feedback,
polyglot Neovim editing, tmux, Git diff and signing, portable Codex preferences,
development and infrastructure tools, and reversible macOS preferences. Existing
Rust and Ollama installations are integrated without replacing their runtimes
or automatically downloading models. MLX-LM has a pinned Python 3.12 requirement
set for an explicitly prepared environment; runtime replacement requires a
private backup and verification before changing the stable environment link.

## Scope

A fresh checkout can preview and install terminal, Git, Codex, workspace, dev,
reverse engineering, Apple development, infra, AI, apps and macOS groups. All authored configuration and automation live
in ~/src/dotfiles; the target host is an Apple M1 Max MacBook Pro.
Existing configuration is backed up and can be restored
without overwriting later user edits. Dependencies are declared in Brewfile;
configuration installation does not upgrade or remove unrelated packages.
Git identity and SSH signing stay machine-local. Codex authentication,
sessions, databases, plugins and approval history never enter Git.

Podman is the intended headless container runtime for Decapod workspaces.
The repository preserves the local Decapod configuration and authored specs;
its runtime state stays local. VM startup troubleshooting is deferred to the
upstream issue rather than expanded into this dotfiles change.

## Acceptance Criteria

- Scoped install, repeated install, restore and failure rollback are exercised
  by tests/test_install.py in isolated temporary home directories.
- The actual Mac's Ghostty, shell hooks, Neovim and Rust LSP are verified
  separately from portable CI.
- Shell configuration makes local Rust and model tools callable; models and
  services start only through explicit user commands.
- Publication requires authorization for the current task; workstation setup
  alone does not authorize pushing or merging repository changes.

The dev group supplies native build/media tools and copied mise defaults for
Node 24.18.0/npm 11.16.0 with project version-file selection. The reverse group
supplies Ghidra/JDK and additive shell discovery. The apple group supplies mas;
scripts/setup-xcode performs explicit interactive Xcode/iOS setup. Apple account
authentication, license review and development signing remain local activities;
no identity, Team ID, certificate, provisioning profile or credential is tracked.

The macOS group manages explicit user preference keys with typed backups,
readback verification and guarded restoration. Chrome is declared for fresh
machines while existing unmanaged installations are preserved. No security
controls or credentials are changed.

## Constraints

The workstation rice keeps Tokyo Night Storm consistent across Ghostty, fzf,
Starship, tmux, Neovim and Git tools. It adds a quieter local prompt, a steady
cursor, file/directory previews, a top tmux bar with pane navigation, a Neovim
workbench/tabline/static indent guide, a shorter hardware summary, Finder list
view and a compact Dock. Configuration is applied through the backed-up installer
from a retained checkout. Application delivery and project signing are separate
tasks; future agents must ask the user to select any Apple development team.

Excluded: Herdr, Tailscale/AMP services, secret migration, unsolicited model
downloads, account setup, VM startup troubleshooting and modifying Decapod itself.

<!-- decapod:declared-capabilities:start -->

## Declared Capability Surfaces

These declarations select authoring and proof obligations; they do not attest implemented runtime guarantees.

- `external-integrations`
- `persistent-state`

<!-- decapod:declared-capabilities:end -->

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `60748b35822094592834a86196c34c2bfa40d4d9855ae3240bf34f0c4016250a`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (4 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
