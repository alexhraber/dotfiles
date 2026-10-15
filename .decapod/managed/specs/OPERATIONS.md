# Operations

## Service Level Objectives

This is local configuration tooling without a hosted availability objective.
Installation must preserve unrelated configuration, produce private recovery
manifests and converge on repeated apply. Dependency/network installation time
depends on independently managed services; no fixed latency is promised.

## Monitoring

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
startup that adds --gui. VM state remains local. A headless ARM64 engine and
the owned verification container have run successfully; earlier failed startup
attempts remain separate diagnostic history. Preserve unrelated engine state.

Keep Ollama stopped between sessions. aiup runs the server in a terminal with
no model preload and zero default keep-alive; Ctrl-C shuts it down. The server
is never enabled during shell initialization or configuration installation.

Follow Decapod's task/workspace lifecycle for agent coordination. Its generated
state is managed through CLI/RPC. Repository-local proof and hosted CI remain
separate evidence; inspect actual validation results before publication.

## Incident Response

Desktop configuration installation starts nothing. Explicitly enable with
scripts/dotfiles desktop apply; inspect fresh PID-bound health with desktop
status. Use desktop permissions for the local SketchyBar Accessibility probe.
Native quick-panel approval and LuLu filter approval are local OS actions.
Only SketchyBar and local.dotfiles.desktop-edge start with this profile;
Borders stays stopped and AeroSpace starts disabled. Models stay manual.

desktop undo restores the native menu first, then original typed Dock/menu
defaults, matching connected displays' wallpaper/options and service state.
Reapply retains the original baseline. Later managed preference edits block
restoration; preserve a newer manually chosen wallpaper before undo. Installer
file restoration is separate. Recheck private APIs after major macOS updates.

ai prepare/status/undo manage the pinned native MLX environment without models.
Prepare verifies Python/packages/Metal before switching the stable path; undo
retains prepared environments and caches. These manifests are local recovery
records, not whole-machine backups. No backup destination or automatic personal
file backup policy has been selected by this repository.

Use the printed private backup manifest with install.sh --restore --dry-run,
then restore after inspection. Later edits or corrupt backups block the operation;
preserve both versions and reconcile them explicitly. Package/model stores and
VM disks are external state, not configuration rollback. Never delete unknown
container resources or signing assets to make diagnostics pass.

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

- Repository signal fingerprint: `0229f36eed59a21f78229356fd3e926ab6826ee2829f8997aff2adce917fbf19`
- Significant implementation surfaces: `.config/` (3 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (7 files), `tests/` (5 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
