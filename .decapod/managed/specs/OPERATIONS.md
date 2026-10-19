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
status. Use desktop permissions to request access from Desktop Controls itself.
On macOS 27 this permission is called Device Control and Data Access; older
systems call it Accessibility. After manual approval, rerun that command to
verify the current healthy helper and restart it, refreshing fullscreen windows
without rebuilding or signing a new app.
Native quick-panel approval and LuLu filter approval are local OS actions.
Wi-Fi uses the themed Desktop Panels adapter when its own Accessibility and
Screen Recording approvals are present; Location stays off. Install it with
desktop panels-setup. desktop panels-permissions requests one pending approval
per call and returns success only after actual readiness. Those approvals are
now verified for the installed signed app. Unsupported/unapproved systems open
the real system picker directly on hover.
No Wi-Fi Access setup command or consent helper is part of the profile.
The themed list keeps native choice order, connected first and up to three
alternatives; explicit Other Networks expansion adds further real choices.
Opening another pane closes Wi-Fi, while bar autohide retains it.
Rollback is the scoped installer backup plus the preceding committed branch
state; do not rebuild Desktop Controls or reset its working OS permissions.
Only SketchyBar and local.dotfiles.desktop-edge start with this profile;
Borders stays stopped; AeroSpace is disabled, quit and not a dependency. Models stay manual.

For main-app updates, controls-setup stages a registered bundle and
controls-permissions requests that build's own AX, then Calendar permission.
An active apply refuses a not-yet-approved replacement before changing live
state. Available local development signing identity stays in Keychain; a distinct
bundle ID separates this signed migration from legacy ad-hoc approvals. Runtime
updates save their previous helper link, LaunchAgent, manifest and appearance
under private desktop/updates/. On owner request, obsolete cached builds may be
archived; removing a legacy consent record means that old binary would require
approval again if restored. Never reset the current app's records for an update.
Desktop Panels keeps its existing identity for Wi-Fi and window-only previews.

The selected palette generates backed-up application files and a private contour
wallpaper. Ghostty's Reload Configuration applies it to existing terminals;
Neovim reloads on FocusGained and a new shell loads prompt/fzf colors. Only an
already-running tmux server receives theme changes. Launcher and previews are
short-lived auxiliary modes, not login services. The original wallpaper archive
remains the desktop undo baseline; installer restore is a separate transaction.

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

- Repository signal fingerprint: `c651940cee68383c9f25d55e5530df3d639c5b9eeeffbcda48ab3da369c9c502`
- Significant implementation surfaces: `.config/` (6 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (14 files), `tests/` (9 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
