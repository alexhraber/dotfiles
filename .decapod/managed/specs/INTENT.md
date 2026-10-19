# Intent

## Product Outcome

Provide a repeatable macOS terminal and development environment for Alex:
Ghostty with a shared desktop palette and Nerd Font, zsh navigation and feedback,
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

The workstation projects the selected desktop palette into Ghostty, fzf,
Starship, tmux and Neovim, with the existing vendored Git themes retained. It adds a quieter local prompt, a steady
cursor, file/directory previews, a top tmux bar with pane navigation, a Neovim
workbench/tabline/static indent guide, a shorter hardware summary, Finder list
view and a compact Dock. Configuration is applied through the backed-up installer
from a retained checkout. Application delivery and project signing are separate
tasks; future agents must ask the user to select any Apple development team.

Excluded: Herdr, Tailscale/AMP services, secret migration, unsolicited model
downloads, account setup, VM startup troubleshooting and modifying Decapod itself.

## Fullscreen desktop and on-demand inference

The owner requested all four refinements: transparent dock window previews,
reliable native fullscreen transitions, coordinated application/wallpaper styling,
and consistent native pane interactions. AeroSpace stays disabled and quit;
no tiling manager or alternate Space shortcut is introduced. Window cards use
actual AX windows and on-demand in-memory captures, with exact selection and
minimized-window restoration. The themed application search opens installed
bundles from the Apple pane or explicit CLI, without a global shortcut or daemon.
The six-hour/six-day weather layout and Location-off Wi-Fi behavior are retained.
Signed main-app migration has a distinct bundle identity and stages permissions
before replacing the working helper. Local signing identities remain untracked.

The refined desktop offers Graphite slate/champagne/ice-blue styling across native
controls. From the far right inward: notifications, clock, weather, then all
other controls. The left side replaces the decorative workspace affordance
with only the Apple logo and active application. Clicking the app name opens
a pane containing its actual app/File/Edit/View/Window/Help/etc. headings;
hovering each heading reveals its real commands and further submenus. Accessibility reads and presses the owning app's actual commands;
disabled commands and submenus are retained, with no invented per-app actions.
Local macOS consent is required and remains a user action.
The right-hand composition has four separated groups: hardware, device/power
controls, clock/weather and notifications. A fifth battery-only pill is folded
into device controls. Hover highlights communicate targeting immediately.
Graphite is the fresh-install default; the other four palettes remain selectable.
Selection colors are explicit palette values with readable foreground contrast.
Native descriptors carry real bar anchors and pin intent, with request-bound
dismissal acknowledgments. Hover previews; click pins; Escape, an outside click
or clicking the same control dismisses. Compact panels retain their top edge
and scroll position on refresh, without global keyboard or desktop shortcuts.
Sound and display panes must follow system keyboard level changes while still
hovered or pinned, without pointer reentry or idle device polling.
The Apple icon should work like a normal system menu on click, with About This
Mac, Settings and useful system/session entries. It uses the same themed pane as the active-app menu, with click selection,
outside-click dismissal, repeated-click dismissal and Escape. Core information/settings actions must not
depend on Accessibility to another application's menu. Current-app menu headings
are nested under the click-only app-name control and use the actual AX menu
bridge and its local OS permission. No separate menu headings occupy the bar.
The owner explicitly approves the weather pane's current layout: preserve its
header and hourly strip. Add six matching daily icon cards immediately below,
starting tomorrow, with Fahrenheit highs/lows and forecast-local day boundaries.

The owner's desired Wi-Fi result remains a themed hover with the connected
SSID and up to three actual nearby networks ranked by recent use, with Location
off. The themed adapter now displays actual native choices and connection state;
the native list supplies ordering rather than an independently verified recency rank.
The functional fallback opens
Apple's actual Wi-Fi picker directly on hover, eliminating the rejected custom
permission/setup wall and extra handoff click. Apple owns list styling, grouping,
availability and connection progress; those are not claimed as a custom list.
Location stays off, no authorization question is presented by hover, and no
password is read or passed by dotfiles. Sound and Bluetooth use the Apple/app menu visual language:
one full-row target, quiet hover, current selection/state and clear action text.
Connected Bluetooth devices precede disconnected ones. A hidden native pin must
not block subsequent fullscreen hover or click interactions.

The Bluetooth header's On/Off label is now its only power action; paired-device
rows retain their Connect/Disconnect behavior. Desktop Panels renders that
change without replacing the approved Desktop Controls executable. A separate
native Wi-Fi adapter and throughput sampler are implemented and its own
Accessibility/Screen Recording approvals have been verified through normal launch.
Location remains off. Native-picker fallback remains available; implemented
native authentication is left to macOS and has not been tested by changing the owner's connection.
Wi-Fi follows Bluetooth's row layout: a header power action, connected network
first, at most three nearby alternatives initially, and
Connected/Not connected labels with explicit hover actions. Native network
options follow the flat list; raw macOS group headings do not create extra rows.
Explicit Other Networks expansion adds up to three further native choices and
survives periodic refresh for that hover request. Fullscreen hover, real rates,
connected state and expansion persistence have passed normal registered-app checks.

The clock is a native Sunday-first month grid and selected-day agenda, with
today/month navigation, event dots and per-calendar source selection. EventKit
reads calendars synced through macOS Internet Accounts, including Google when
the user enables it there. No OAuth tokens or event content enter Git; events
stay in memory. Hardware, sound, display, connectivity, battery, notifications
and weather share native panels with usable hover bridges and explicit actions.
Their visual hierarchy uses symbol headings, large current readings, bounded
capacity meters, telemetry detail cards and readable trend graphs. Weather
offers a six-hour cached outlook beginning next hour, with imperial units for the declared ZIP;
hovering never initiates a forecast fetch. Dock motion should follow the
display refresh rate, settle without continual animation redraws, and respect
Reduce Motion while retaining its entirely transparent icons-only appearance.
The helper reads events only even though macOS requires Full Calendar Access.
Its bar label must show current macOS hours/minutes with seconds hidden, refresh every second
even when hidden, and update immediately on reveal and wake. A correct system
clock must never appear minutes behind through a stale cached display. This
uses macOS time synchronization and adds no NTP client or clock daemon.

The top bar should feel restrained and predictable. Section pills are separated
by a space-sized gap with no background
connecting them. Islands is the reproducible default.
CPU/GPU/memory use icons
instead of words; concise fixed-width CPU/GPU utilization and used memory leave
temperatures and other details in hover panels.
Pointer movement must not leave delayed panels behind, close panels during a
short crossing into them, or shift targets through reveal animations or samples.
Existing controls, imperial units, pinned weather and far-right notifications
remain part of the single autohiding fullscreen surface.

The dock is icons only: its background is fully transparent, with no glass,
shelf, border, shadow, label, badge or active marker. Autohide, magnification,
application grouping and right-click actions remain. Bar themes and pinned
ZIP97750 weather are independent of this visual simplification.
Clicks use the normal macOS reopen request for running apps, including apps
without a visible window. A Dock-process-only mouse-motion filter suppresses
the native bottom-edge reveal when Accessibility is available, except during
Mission Control. Undo removes this filter.
Icons sit at the screen bottom and reveal when the pointer reaches their
future footprint, removing the extra upward movement. Resting size is preserved;
peak hover magnification increases by 25% within the available screen width.

The explicit desktop profile supports the owner's native fullscreen workflow:
one autohiding SketchyBar, no competing native menu, and an open-apps-only
AppKit dock with magnification and one icon per open application. Notifications belong
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

## Display management

The monitor item replaces the brightness-only sun icon. Brightness is one
control in a broader Display pane: actual connected-screen dimensions and
main/extended/mirror state, native Dark Mode/Night Shift/True Tone switches,
and freshly discovered nearby AirPlay/Sidecar screens. Pairing and content
confirmation remain under macOS control, initiated only by an explicit click.
Arrangement, scaling and device-specific refresh settings remain in Display
Settings. Gold filled Sound/Display tracks match capacity meters through the
shared accent palette. Native input, keyboard-level refresh, fullscreen Spaces,
Location-off operation and stable existing consent identities are preserved.

<!-- decapod:declared-capabilities:start -->

## Declared Capability Surfaces

These declarations select authoring and proof obligations; they do not attest implemented runtime guarantees.

- `external-integrations`
- `persistent-state`

<!-- decapod:declared-capabilities:end -->

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `2ecf78b493a6390b0233c22d537c0f69655d248ed53759d610299422faf02a4c`
- Significant implementation surfaces: `.config/` (6 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (14 files), `tests/` (9 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
