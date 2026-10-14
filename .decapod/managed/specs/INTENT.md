# Intent

## Project purpose

Provide a repeatable macOS terminal and development environment for Alex:
Ghostty with Tokyo Night Storm and Nerd Font, zsh navigation and feedback,
polyglot Neovim editing, tmux, Git diff and signing, portable Codex preferences,
development and infrastructure tools, and reversible macOS preferences. Existing
Rust, Ollama and MLX installations are integrated without replacing their
runtimes or automatically downloading models.

## Outcomes and boundaries

A fresh checkout can preview and install terminal, Git, Codex, workspace, dev,
infra, AI, apps and macOS groups. All authored configuration and automation live
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

## Acceptance and scope

- Scoped install, repeated install, restore and failure rollback are exercised
  by tests/test_install.py in isolated temporary home directories.
- The actual Mac's Ghostty, shell hooks, Neovim and Rust LSP are verified
  separately from portable CI.
- Shell configuration makes local Rust and model tools callable; models and
  services start only through explicit user commands.
- The authorized publication target is alexhraber/dotfiles main.

The macOS group manages 14 explicit user preference keys with typed backups,
readback verification and guarded restoration. Chrome is declared for fresh
machines while existing unmanaged installations are preserved. No security
controls or credentials are changed.

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

- Repository signal fingerprint: `bd87ea8ea1effbcd9214006f360947918b918f94b45b80ee867599d5e1d77e51`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (3 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
