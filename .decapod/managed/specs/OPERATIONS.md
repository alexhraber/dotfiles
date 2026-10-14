# Operations

Preview installation with install.sh --dry-run. Use --deps for the selected
Brewfile dependencies, --all for all configuration groups, and exec zsh -l to
load a fresh shell. Backups and restore commands are described in README.md.
Use scripts/dotfiles doctor --all to inspect configuration drift and dependencies.
Rebuild bat's cache after theme changes; the installer does this automatically.

Git signing uses the existing public key and machine-local identity. Register
that public key for authentication and signing with GitHub. Do not move private
keys, account sessions or credential helpers into the repository.

Rust PATH setup sources ~/.cargo/env when it exists. Neovim's Rust LSP requires
rustup's rust-analyzer component. MLX uses its existing virtual environment;
Ollama uses the existing installation and model catalog. Neither is started by
shell initialization.

Podman on macOS needs a Linux VM. Use normal quiet machine startup, never debug
startup that adds --gui. VM state remains local. The current setup preserves
failed first-boot attempts for diagnosis; this change does not claim that
container execution succeeded. The upstream GUI issue has the detailed context.

Follow Decapod's task/workspace lifecycle for agent coordination. Its generated
state is managed through CLI/RPC. This project's generic readiness adapter is
not available in Decapod 0.111.1; record that result honestly and retain actual
repository-check evidence separately.

<!-- decapod:capability-overlay:persistent-state:start -->

Generated capability obligations: `persistent-state` is declared for this project. These are decisions and proof requirements, not claims of implemented behavior. Resolve each against project source and tests; record unsupported or non-applicable mechanisms explicitly.

## Persistent State Operations Overlay

### Backup & Recovery
- Backup scope, schedule, retention, and restore evidence MUST be selected for the project
- Recovery point objectives MUST be explicit project decisions, not assumed values
- Recovery time objectives MUST be explicit project decisions, not assumed values
- Restore verification cadence MUST be recorded with the operational proof plan

### Migration Operations
- All schema changes via migration files
- Migration rollback procedures documented
- Migration downtime and availability effects MUST be declared; zero downtime requires project-specific proof
- Migration health checks and rollback triggers
<!-- decapod:capability-overlay:persistent-state:end -->

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `6fba237828fbded719d7d827b3c1a53e8a4cf4a6874d4d4993811e935e34eac4`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (1 files), `tests/` (1 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
