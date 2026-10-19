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
No injection, SIP change or cursor warping is required. A CGEventTapCreateForPid
filter targets only the native Dock’s mouse-motion events at the outer bottom
two points. It requires Accessibility, excludes connected-display seams and
detected Mission Control, reattaches after Dock restarts, and detaches on health failure
or restore. Other event types pass unchanged.
DockView.step uses elapsed-time exponential smoothing rather than per-frame
increments, with exact settlement tolerances and an animation timer capped to
the target display's 30–120 Hz range. Settled animation ticks do not invalidate
the view; the existing app-list refresh still redraws artwork periodically.
Reduce Motion snaps zoom and pointer tracking directly to their targets.

.config/sketchybar contains rounded control groups and Python hover plugins.
The default islands layout draws four separate right-side section backgrounds:
hardware, devices/power, clock/weather and notifications. Three eight-point
empty items separate their bounds; bracket background padding
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
readout without moving adjacent pills. Graphite is the fresh default, combining
charcoal with champagne and ice-blue accents. Nocturne remains available with
violet and cyan accents. Native panels are opaque and blur-free.
themes.json and plugins/appearance.py own five validated palettes and the
ribbon/islands layout. A single live IPC update restyles existing items and
toggles bracket backgrounds, preserving visibility and popovers. The native
helper reloads the selected palette on SIGUSR1 or its health interval; native
controls/calendar restyle and menus close for a coherent next open.
The dock uses application artwork with a transparent background,
so palette changes affect the bar and popovers without recoloring app icons.

controls.item_anchors snapshots up to eight finite visible SketchyBar item
rectangles when an item event opens a panel. control-panel.m converts these
CoreGraphics coordinates to AppKit, aligns the panel beneath its item and
clamps it to its display. Device panels use 320 points, hardware/power 344,
and the existing weather composition retains 380 points. Content identity
excludes request metadata; equal refreshes avoid rebuilding views, same-panel
updates preserve scrolling and tracking defers disruptive readout changes.
Hover previews use exit hysteresis. Clicking pins a native control until the
same item, Escape or an outside mouse-down dismisses it; local panel handling
uses no global event tap or navigation shortcut. A private request-bound
dismissal acknowledgement permits future hover without reviving an old pin.

SketchyBar brightness_change and volume_change events route through status.sh
to controls.refresh_open for the corresponding pane. The backend checks the
active hover request, dismissal acknowledgement and a native status sample
younger than three seconds before querying actual system values. A sample
older than the current open request does not discard an immediate first key.
Device reads run outside the interaction lock. A private device-refresh token
lets only the latest event commit while a second visibility/request check
prevents a slow result from replacing a newer pane or refreshing a closed one.
Transient read failures retain the last good slider. Rendering preserves the
existing request, anchor and pin; native geometry and tracking behavior are
unchanged. This level-refresh path adds no polling loop or native API. The
separate Apple-menu change in this candidate does rebuild the helper.

weather.daily_outlook groups the cached NWS day/night periods by the declared
America/Los_Angeles date and returns tomorrow through six days ahead. The cache
retains fourteen periods, and the verification image includes tzdata. Below
the existing six hourly cards, control-panel.m draws six daily cards using the
same weatherSymbol mapping, tile geometry and colors, with Fahrenheit highs
and lows. Native weather rows omit the former Tonight/day/night list. No
additional network request occurs while rendering either forecast strip.

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
Optional meter values are finite fractions on hardware/battery panels only.
weather.outlook reads the same private forecast cache and emits at most six
future hourly cards with bounded text and an enumerated condition. weather.outlook
filters startTime strictly after now before collecting six cards, so the ongoing
hour stays in the main reading and the strip begins next hour, including at an
exact hour boundary or across midnight. Invalid starts are skipped before the
six-card limit; hover still reads only the private cache. Native
validation checks those fields before rendering SF Symbols, large readings,
two-column telemetry cards, accent sliders and forecast tiles. The weather
backend omits its old hourly text rows in this view; action indices still map
to the original descriptor rows, including the explicit refresh command.
Native callbacks resolve executable Python candidates in versioned ARM/Intel
Homebrew, unversioned Homebrew, then system order. They no longer depend on an
unversioned /opt/homebrew/bin/python3 symlink. DFControlsStatus exposes only a
backend_available boolean; source and device commands retain their fixed argv
boundaries. The selector is exercised independently with executable predicates.
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
scripts/app-menu.m gives the Apple icon a click-only themed MenuPanel. Its
placement uses the bar's explicit y=4 and maximum 40-point height, rather than
adding a second notch-safe-area inset. Fixed enum
actions resolve installed About This Mac, Settings, App Store and System
Information bundles through NSWorkspace. Force Quit presents a native chooser
of running foreground apps with Cancel as the default and acts only after the
user selects an app and confirms. Lock Screen dynamically resolves the installed
login framework's SACLockScreenImmediate symbol; unavailable support disables
the item. Sleep and confirmation-based restart/shutdown/logout use fixed Apple
events to loginwindow. The shared panel loop keeps the bar open until selection
or dismissal; Apple hover only highlights and does not read the AX tree.
The same source reads the frontmost app’s AX menu bar on a background queue.
Apple entries use a validated fixed action enum and the shared MenuRow
renderer; the key-capable MenuPanel supports Escape without AX permission.
DockView uses NSWorkspace openApplicationAtURL with activation enabled and
createsNewApplicationInstance disabled, preserving normal reopen semantics.
desktop.py registers the complete signed bundle through public LSRegisterURL
before activation, including cached builds launched directly by launchd.
controls.py reads Wi-Fi power through networksetup for the bar icon only.
show('wifi') uses the ordinary dwell/request cancellation, hides custom windows,
then opens Apple's real Wi-Fi picker directly using native_item(ensure='open').
A fixed wifi-header AX lookup makes opening idempotent and closing conditional:
a different system panel is never toggled by Wi-Fi cleanup. No SSID is extracted,
no saved-profile choices are synthesized and no scan/consent helper is installed.
active.json marks native_wifi so level/network refresh cannot replace the picker.
Bar conceal retains it while the pointer enters; another themed pane or explicit
cancel closes only a visible Wi-Fi picker. Native outside-click/Escape behavior
owns dismissal. The bounded status-item lookup supports MenuBarAgent hosting
views on macOS 27 and the older ControlCenter menu bar.

desktop-edge.m still emits the fixed desktop_network_changed event without
reading or forwarding network values. Wi-Fi updates its radio icon only; Apple
owns the visible native list. The desired themed top-three recency list remains
unimplemented with Location off. Offscreen AX mirroring was rejected because
compositor probes found visible frames. No change to the approved native binary
or OS privacy settings is needed for this functional fallback.

desktop.py's permissions route requests access from the installed native helper.
It accepts approval only from healthy, fresh status bound to the current
LaunchAgent PID, then restarts that owned helper so windows do not retain their
pre-consent Space membership. An unapproved request opens the OS privacy pane;
it neither grants permission nor restarts the helper. No native rebuild or
signing change is needed after approval.

ControlRow uses the Apple/app menu's shared palette and quiet hover highlight,
with optional selected/detail/hint metadata for output and Bluetooth state.
Desktop Panels (`scripts/wifi-pane.m`) compiles the same renderer with a distinct
distributed-notification name. Its transient `--ui` server owns Wi-Fi/Bluetooth
windows and request-bound private status; other panes keep Desktop Controls.
HeaderPower maps the first On/Off row to index zero, with a power tooltip and AX
button label. The Bluetooth body has no duplicate power action. `setup_panels`
builds/signs/registers a complete auxiliary bundle, backs up its prior link and
publishes it atomically, preserving the Desktop Controls identity and approvals.

The auxiliary Wi-Fi route is gated by its registered app's AX and Screen Capture
status. It captures one display into memory, covers native popup creation and
closing, reads bounded native controls while skipping credential fields, and
returns fresh typed rows. Actions match a fresh role/identifier/text/selected
state before AXPress. Python serializes queries, validates results, preserves
native buttons and the connected network within the 14-row budget, and samples
netstat link counters each second only while its request remains visible. A
four-second snapshot refresh reopens the native controls behind the cover;
performance, connection/authentication handoff and full mouse-hover acceptance
still require live verification after Screen Recording approval. Unsupported or
unapproved systems retain direct native hover. No Location framework is linked.
Labels remain separate from literal device argv actions. DFControlsHide
acknowledges pinned requests even if AppKit already hid their window. Python's
hidden_pin reconciles a pin only against a fresh, healthy, subsequent native
report that explicitly says the panel is hidden. Missing/stale samples preserve
pins, avoiding a race with newly opening panels.

The bar contains only Apple and front_app; status.sh opens the app menu on click,
not hover. Index 1 reads a fresh menu tree for the current PID and renders every
top-level heading except Apple in a themed root pane, preserving order and AX
objects. Hovering a root row opens its actual contents; further submenus retain
a bounded extra depth for the new wrapper. No flat heading slots or overflow
heading are created. Root placement shares the Apple menu’s explicit bar offset.
Click-open panes stay open while the pointer moves away; outside mouse clicks,
Escape, a second app-name click, app/Space changes or another control dismiss.
Local/global NSEvent monitors only dismiss an already-open menu; keys are not
consumed and no desktop shortcut is registered. Menu rows retain actual AX elements, enabled
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

- Repository signal fingerprint: `bbaaa250dd601e1ba58a43bf226c431cad5c743e9e17c15eaae8ac775a8d4d53`
- Significant implementation surfaces: `.config/` (5 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (10 files), `tests/` (7 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
