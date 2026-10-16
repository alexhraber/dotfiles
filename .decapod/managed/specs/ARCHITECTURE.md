# Architecture

## Direction

This repository defines a local workstation, including an optional desktop runtime. Bash entrypoints dispatch
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
- The dev group also copies .config/cargo/config.toml through the same guarded
  backup/restore operations. Cargo uses a local sccache wrapper unless project
  or environment settings override it. Incremental behavior is retained; cache
  data remains private machine state. Hyperfine and ARM macOS macmon are explicit
  tools; no benchmarking, metrics server or startup service is enabled by install.
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

scripts/desktop.py owns an explicit, locked apply/status/permissions/undo
lifecycle. It captures typed defaults, service state and a per-display wallpaper
archive before enabling the profile. Versioned native app bundles live in private
state; a stable executable symlink lets LaunchAgent upgrades restart the new
build without changing its plist. Health binds a fresh status record to the
actual launchctl PID. Reapply retains the original recovery baseline.
compile_tools hashes all native sources/headers and the generic permission
plist, builds in a temporary private directory, ad-hoc signs and verifies the
complete bundle, then atomically publishes it. Failed builds leave no cached
partial bundle or changed active link. No team identity is embedded in source.

scripts/desktop-edge.m uses AppKit/QuartzCore for an open-app dock. One pure
fisheye geometry function owns painting and hit testing. It polls pointer state,
animates only while visible, supports Reduce Motion, and observes application,
Space and display changes. Serial background SketchyBar IPC avoids blocking
animations. SkyLight menu suppression is health-guarded and restored on ordinary
termination or bar failure. A Mission Control observer temporarily suppresses
custom surfaces. Built-in brightness uses dynamically resolved DisplayServices.
No injection, event tap, SIP change or cursor warping is required.

.config/sketchybar contains rounded control groups and Python hover plugins.
The default islands layout draws five separate right-side section backgrounds.
Four eight-point empty items separate their bounds; bracket background padding
is zero so backgrounds cannot expand into the gaps. appearance.apply toggles
the gaps on for islands and off for optional ribbon in the same live IPC update.
Bracket and background drawing are both set directly, without interpolation
of boolean visibility; inactive group backgrounds cannot connect the pills.
The bar stays at y_offset=4 and toggles visibility without sliding its anchors
or popups. Hardware icon labels use fixed widths: CPU/GPU show utilization
percentages and memory shows used GiB; Fahrenheit temperatures, power,
capacity and swap remain in the panels.
The clock has update_freq=1 and explicit updates=on, with desktop_revealed and
system_woke subscriptions. status.sh formats current /bin/date output as
hours/minutes and AM/PM on every event; hiding seconds does not reduce refresh
cadence or retain a previous value. A fixed 74-point label contains the compact
readout without moving adjacent pills. The native
helper is unchanged, retaining its binary identity and existing OS consent.
Nocturne uses charcoal surfaces, violet clock/Apple/notification accents and
cyan hardware/weather icons. Native panels are opaque and blur-free.
themes.json and plugins/appearance.py own four validated palettes and the
ribbon/islands layout. A single live IPC update restyles existing items and
toggles bracket backgrounds, preserving visibility and popovers. The native
helper reloads the selected palette on SIGUSR1 or its health interval; native
controls/calendar restyle and menus close for a coherent next open.
The dock uses application artwork with a transparent background,
so palette changes affect the bar and popovers without recoloring app icons.

DockView.drawRect clears its pixels and draws only application icons. There
is no visual-effect background view, fill, outline, window shadow, badge,
label or active marker. A clear non-opaque panel hosts the view. Hit testing
uses the same fisheye icon rectangles as drawing; blank areas pass mouse events
through, while a larger exit envelope retains autohide hysteresis.
Icon rectangles start at local y=0 and the panel starts at the screen bottom.
The hidden reveal region follows the resting icon footprint, 44 points tall,
instead of requiring a trip to a three-pixel edge beneath floating icons.
Resting size remains 40 points; unconstrained peak grows from 62 to 77.5 points.
Geometry tests cover this ratio, bottom alignment and reveal on offset displays.
controls.py serializes hover state plus descriptor commits under a short
advisory lock. Dwell and device reads happen outside the lock. Anchor exit
cancels pending opens; scripts/control-panel.m owns the native window/anchor
bridge and 320ms exit grace. Typed descriptors contain bounded labels, action
booleans, optional slider percentage and bounded graph samples, never commands.
The helper reads a fixed private path with owner/mode/size/type checks and
O_NOFOLLOW. Native callbacks carry panel, revision and row index/percentage to
the installed backend; stale callbacks are rejected before action selection.
Dismissed request IDs cannot reopen through a late device response. Repeated
hover reuses the same window. Token checks reject stale fresh-data responses.
Cached content renders before fresh device reads. Read-only warmup runs on reveal. macmon samples are shared
through private state and displayed in Fahrenheit, with load graphs and alerts.
scripts/calendar-panel.m owns an EventKit store, 42-day grid and selected-day
agenda. Calendar reads run on a serial queue and stale month responses are
rejected by revision. Permission requests occur only on an explicit local
connect action. Source selection is private; event content remains in memory.
scripts/app-menu.m reads the frontmost app's AX menu bar on a background queue,
mirrors headings into bounded SketchyBar slots with an overflow menu, and draws
native themed dropdowns/submenus. Menu rows retain actual AX elements, enabled
states, marks and shortcut labels. Only a selected enabled leaf in the same
foreground app receives one AXPress. Queries have messaging timeouts and
bounded item/depth limits; commands are never executed on hover. App/Space
changes dismiss menus. Menus, calendar and control windows exclude each other.
Device operations use argv arrays. Native Wi-Fi/notification/Focus panels need
local Accessibility/Automation. scripts/set-wallpaper.swift captures/restores
per-display URLs and typed image options in a private archive.

plugins/weather.py reads the declared ZIP97750 point from weather.json, resolves
NWS grid links daily, and fetches hourly/extended forecasts concurrently with
five-second request deadlines. Private cache, an exclusive refresh lock,
15-minute freshness interval and failure cooldown avoid repeated traffic. Hover
only reads cache; a completed one-shot fetch updates an open weather popup.
Stale data retains its original age and is labeled cached. Temperature formatting
handles Fahrenheit and Celsius/quantitative input, always displaying °F.

scripts/local_ai.py prepares a versioned Python 3.12 MLX environment, verifies
the package pins and Metal before atomically changing the stable link, and
preserves the original link/directory in private state. It loads no model.
The generic installer, desktop lifecycle and AI lifecycle are distinct
transactions with separate recovery state.

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

- Repository signal fingerprint: `2ed975429e5acb516732c32f96a4c54cfef1dd0e8b32ed314e2cb29c52d86e47`
- Significant implementation surfaces: `.config/` (4 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (10 files), `tests/` (6 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
