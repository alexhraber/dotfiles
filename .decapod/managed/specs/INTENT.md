# Intent

## Project purpose

Provide a repeatable macOS terminal and development environment for Alex:
Ghostty with Tokyo Night Storm and Nerd Font, zsh navigation and feedback,
Neovim editing, Git diff and signing, and portable Codex preferences. Existing
Rust, Ollama and MLX installations are integrated without replacing their
runtimes or automatically downloading models.

## Outcomes and boundaries

A fresh checkout can preview and install selected terminal, Git, Codex and
workspace groups. Existing configuration is backed up and can be restored
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

Excluded: Herdr, Tailscale/AMP services, macOS system preferences, secret
migration, unsolicited model downloads, and modifying Decapod itself.

<!-- decapod:declared-capabilities:start -->

## Declared Capability Surfaces

These declarations select authoring and proof obligations; they do not attest implemented runtime guarantees.

- `external-integrations`
- `persistent-state`

<!-- decapod:declared-capabilities:end -->

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `6fba237828fbded719d7d827b3c1a53e8a4cf4a6874d4d4993811e935e34eac4`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (1 files), `tests/` (1 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
