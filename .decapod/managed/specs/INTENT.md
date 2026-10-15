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
reverse engineering, Apple development, infra, AI, apps, desktop and macOS groups. All authored configuration and automation live
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

Routine operations use the existing installer, check, doctor and editor scripts
directly. The owner does not use Just; its convenience wrapper and dependency
are removed without removing any underlying operation or required check.

The workstation rice keeps Tokyo Night Storm consistent across Ghostty, fzf,
Starship, tmux, Neovim and Git tools. It adds a quieter local prompt, a steady
cursor, file/directory previews, a top tmux bar with pane navigation, a Neovim
workbench/tabline/static indent guide, a shorter hardware summary, Finder list
view and a compact Dock. Configuration is applied through the backed-up installer
from a retained checkout. Application delivery and project signing are separate
tasks; future agents must ask the user to select any Apple development team.

Excluded: Herdr, Tailscale/AMP services, secret migration, unsolicited model
downloads, account setup, VM startup troubleshooting and modifying Decapod itself.

## Fullscreen desktop and on-demand inference

The explicit desktop profile supports the owner's native fullscreen workflow:
one autohiding SketchyBar, no competing native menu, and an open-apps-only
AppKit dock with magnification and grouped window counts. Notifications belong
furthest right. Hover panels expose sound, built-in brightness, Wi-Fi, Bluetooth,
calendar, battery and CPU/GPU/RAM details; every displayed temperature is °F.
Motion, typography, spacing and cached response are part of the product intent.
Accessibility approvals remain local and unapproved quick panels remain a gap.
Weather is fixed to user-requested ZIP97750 and the official NWS ZIP forecast
point, with a compact bar item, immediate cached hover, Fahrenheit/mph, upcoming
hours and extended outlook. No machine geolocation or API key is involved.

Native fullscreen Spaces and trackpad gestures are retained. macOS requires
one regular Desktop; this setup neither destroys it nor invents alternate
desktop keyboard bindings. AeroSpace starts disabled and Borders is optional.
desktop apply/status/permissions/undo provide explicit lifecycle and recovery.
The installation itself starts no services. The enabled desktop starts only
SketchyBar and its edge helper; Ollama remains manual with no model preload.
ai prepare/status/undo make the pinned MLX environment reproducible without
loading models, preserving the original environment and guarding later edits.

<!-- decapod:declared-capabilities:start -->

## Declared Capability Surfaces

These declarations select authoring and proof obligations; they do not attest implemented runtime guarantees.

- `external-integrations`
- `persistent-state`

<!-- decapod:declared-capabilities:end -->

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `c55e37c9730ea2f3cd8d6824221a63811dead18e1216de1c705a501150254036`
- Significant implementation surfaces: `.config/` (4 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (7 files), `tests/` (6 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
