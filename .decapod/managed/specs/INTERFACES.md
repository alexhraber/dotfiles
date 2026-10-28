# Interfaces

## Inbound Contracts

install.sh accepts --groups with any comma-separated subset of terminal, git,
codex, workspace, dev, reverse, apple, infra, ai, apps, desktop and macos, plus --all, --deps and
--dry-run. The default group is terminal. scripts/dotfiles doctor uses the same
group selection. Restore accepts a manifest via scripts/dotfiles restore or
install.sh --restore; dry-run previews both operations.

Git signing requires the git group, --git-name, --git-email and --signing-key
pointing to an existing public SSH key. No private key is copied. Invalid
arguments, directory conflicts, failed subprocesses and failed filesystem
operations return nonzero with diagnostics.

## Data Ownership

Version 1 contains repository and changes. Each operation records target,
original state, installed state and a backup path when the original existed.
States are absent, symlink with link value, or file with SHA-256 and mode.
Resolved symlink contents are also retained for inspection. Restore verifies
backup state and rejects current contents differing from both original and
installed states. The manifest is local and should be treated as trusted input.

macOS preference manifests have version 1 and kind macos-preferences, with
domain/key changes containing typed original and installed values. An absent
original key is null. The same restore CLI dispatches to per-key restoration
on macOS and rejects later edits before writing any preferences. Configuration
files and preferences use separate manifests and application transactions.

## Shell and editor

proj chooses directories under PROJECTS_DIR (default ~/src). wt selects
worktrees; wtnew takes a new branch and explicit directory. Paths with spaces
are supported. mlx/mlxchat/mlxserve use MLX_ENV or ~/.venvs/mlx; cxlocal uses
CODEX_LOCAL_MODEL or the installed qwen3-coder:30b model through Ollama.
aiup explicitly starts Ollama in the foreground with no model preload and a
zero keep-alive default, Flash Attention enabled, and q8_0 KV cache. Ctrl-C in
that terminal stops the server. No helper registers a login service; clients
may override keep_alive per request. Existing background services must be
stopped separately with brew services stop ollama.
cws takes an explicit container image and optional command, mounts only the
current project, and requires an already-running Podman engine. It never starts
a VM. tm attaches or creates the main tmux session with the standard prefix.
Neovim's leader is Space; mappings and local.lua extension are documented in
README.md. Codex profiles use separate top-level TOML files.

Ctrl-T previews files with bat, Alt-C previews directories with eza, and Ctrl-/
toggles previews. Tmux retains Ctrl-b: h/j/k/l select panes, Shift-h/j/k/l resize,
Tab switches to the previous window. Neovim Space ss opens the workbench;
[b and ]b switch buffers. The selected desktop palette is projected into the terminal, editor, tmux and shell.

Routine workflows invoke install.sh, scripts/check, scripts/dotfiles doctor,
scripts/editor_check.py and Homebrew directly. No Just task runner or wrapper
is required. scripts/editor_check.py validates installed language servers in
disposable fixtures rather than changing project files.

The dev group copies .config/mise/config.toml; mise install explicitly installs
the declared Node/npm defaults. It also copies generic Cargo configuration with
a local sccache wrapper to ~/.cargo/config.toml through backed-up operations.
Project settings and RUSTC_WRAPPER can override it; existing files are backed up
before replacement. sccache --show-stats inspects the on-demand cache; macmon and
hyperfine are explicit monitoring and benchmark commands. No service is enabled.
The reverse group copies zsh/reverse.zsh and
adds its source to .zshrc.local, retaining other settings and explicit Java/Ghidra
choices. The apple group installs mas on macOS; scripts/setup-xcode requires a
visible local terminal and installs Xcode, selects it, presents Apple's license,
runs first-launch setup and downloads iOS. Signing uses local Xcode account
assets and command-line build overrides; no team or signing identity is tracked.

## Outbound Dependencies

Homebrew, GitHub Git transport, rustup/Cargo, Ollama, MLX and Podman remain
independently managed. Native Neovim package installation fetches pinned plugin
commits on first startup. The optional desktop profile authors a local user
LaunchAgent and SketchyBar events; it exposes no network service API.

## Desktop and inference lifecycle

controls-setup builds/registers a staged main app without changing the active
helper. controls-permissions requests its Accessibility first and Calendar only
on a subsequent approved invocation, returning nonzero until both are true.
An active apply checks the exact candidate's normal registered-app status before
any appearance/live-helper change. Main bundle and launchd identities are
separate, allowing signed migration without resetting the working app's records.
launcher requests the themed installed-application search; no global binding is
registered. Apple Search Applications opens the same pane.

panel-request.m exchanges mode, random request ID, PID, Cocoa anchor and timestamp
in private JSON. Reads reject symlinks, wrong ownership/mode, malformed fields and
stale requests. Hide writes a fresh cancellation request before broadcasting;
dock autohide preserves an explicit launcher, while Space/overview/undo cancels
all pending modes. workspace-status.json reports only counts, visibility, geometry,
request freshness and fixed error codes, never app/window titles or image pixels.

Dock hover cards include titled windows on inactive fullscreen Spaces, merged
with the accessible AX list by capture ID and unambiguous geometry/visibility.
AX cards revalidate process and window membership; minimized windows are restored.
Capture-only cards revalidate their live capture identity on click, activate the
app through native Spaces, and retry exact AX resolution for at most 800ms. When
unresolved, activation follows the app's native last-window behavior. Snapshots
use window-only filters and existing Screen Recording approval, with no display
recording stream. `wifi-pane --workspace-diagnostics [--capture]` reads the same
cross-Space inventory and optionally captures one transient image per app,
returning only bundle identifiers, counts, permission booleans and numeric error
codes. It never opens a pane, activates an app, or serializes titles/images/IDs.
`workspace-status.json.scan.shareable` counts usable shareable candidates. The
application picker uses case/diacritic-insensitive local matching, arrows, Return,
Escape and click, opening existing instances. AppKit pane animation is anchored
and respects Reduce Motion. No Space creation/deletion or navigation remapping occurs.

scripts/dotfiles desktop apply explicitly starts SketchyBar and the native
edge helper, sets backed-up menu/Dock defaults and wallpaper, then requires
fresh PID-bound health. status reports runtime health. permissions requests
Device Control and Data Access from Desktop Controls, accepts only fresh status
from its current healthy PID, and restarts the owned helper after approval to
refresh fullscreen windows. If unavailable, it opens local OS approval settings. undo restores the native menu first, then guarded preferences,
wallpaper and prior service state. It retains configuration and packages.

The top three pixels reveal the bar; the bottom-center resting icon footprint
(44 points tall) reveals the dock after an 80 ms dwell. Icons grow upward from
the screen bottom, with no 26-point gap to chase. Resting size stays 40 points;
unconstrained peak hover size is 77.5 points, 25% above the previous 62 points.
Crowded layouts scale to fit. Exit hysteresis is 320 ms. Hover controls
include calendar, sound/output/mute, built-in brightness, a directly hovered native Wi-Fi picker,
paired Bluetooth devices, battery and Fahrenheit CPU/GPU telemetry. Notifications
are furthest right; hardware warnings are not an unread notification count.
From that right edge inward, clock and weather come immediately after
notifications. Only the Apple logo and foreground-app name occupy the left. Apple opens a themed system pane only on click, with About This Mac,
System Settings, App Store, System Information, Force Quit and session/power
entries. Native tracking supports selection, outside-click dismissal and Escape.
Information/settings entries do not require AX access. Force Quit is a native
app chooser; restart/shutdown/logout request the OS confirmation dialogs.
Clicking the app name opens a pane listing all actual top-level menus except
Apple, including the app’s own menu. Hovering each row reads and opens its real
contents; clicking enabled leaf commands uses AXPress, with submenus, disabled
states, marks and shortcut labels retained. App-name hover only highlights.
The pane supports second-click toggle, outside-click dismissal and Escape. This
requires Desktop Controls Accessibility approval. No app-menu data is persisted.
The private helper status adds app_menus.apple_items for the fixed menu's count.
Clock labels use local 12-hour hours/minutes and AM/PM with seconds hidden, sourced from macOS once
per second while shown or hidden. Reveal and wake also request a fresh value.
The calendar hover/click interface is unchanged; no new service, time-setting
command or independent NTP/network synchronization is introduced.
Native quick panels need local OS permissions. No desktop-navigation keyboard
substitute or automatic Space destruction is installed.

The main bar represents CPU, GPU and memory with distinct Nerd Font icons,
not text names. Fixed-width labels show CPU/GPU utilization percentages and used
memory in GiB (`G`); temperatures in °F, total capacity, swap, power and fans
remain available on hover.
Sound and brightness are icons alone. Heat and swap warning colors remain.
The bar reveals in place at y_offset=4. A 120ms hover dwell is canceled by exit;
native window/anchor geometry and 320ms grace support crossing into panels.
Reentering an open panel does not close/reopen it. Only actions highlight.
The internal controls.py changed volume|brightness callback refreshes an
already-open matching pane after the corresponding SketchyBar system event.
It reads the actual level rather than trusting event text, retains the hover
request/anchor/pin, and rejects hidden, stale, dismissed or superseded work.
Keyboard and other system level changes update the slider and numeric reading
without pointer reentry; closed panes add no device polling.

Clicking a running app uses the macOS reopen request without requesting a new
instance. Wi-Fi hover/click uses the custom pane. Discovery failures render a
concise unavailable status instead of opening the native picker. Legacy owned
pickers are closed conditionally through the fixed wifi-header on pane switches.
Bar conceal retains an explicit custom request; cancellation and pane switches
close it. Native network names and order come from the covered adapter and stay
in private runtime snapshots. No Location request, password read or credential
write is added. Sound/Bluetooth rows retain bounded detail/hint/selected metadata
and literal device argv actions; network change events carry no network values.

The Desktop Panels adapter reads actual choices when its registered-app status
reports supported, Accessibility and Screen Capture. Missing access produces the
custom unavailable status without opening another system pane.
`desktop panels-setup` installs it; `desktop panels-permissions` requests the two
OS approvals without requesting Location.
Permission requests are staged: Accessibility first, Screen Recording on a
subsequent approved call, and actual access readback before success is reported.
Setup/build never grants or requests those permissions. The adapter's `--snapshot`/`--action` response
JSON has a fresh sampled timestamp, bounded typed rows and handoff status; the
UI renders literal native network names/actions, connected state and current
interface byte rates. As in Bluetooth, connected rows come first with a checkmark
and Connected label; up to three alternatives show Not connected and Connect on
hover. Native options follow; native category headings are omitted. Other Networks
adds up to three actual other choices when expanded. Request-bound expansion is
replayed by --snapshot/--action with --expanded, preserving it across refreshes.
Normal registered-app OS approval, fullscreen hover, connected state, rates and
expansion persistence are verified. Network switching/authentication remain untested.
Rate-only redraws retain the callback revision; a changed request/action mapping
invalidates it. Intentional native handoff allows an empty row list, closes the
custom request and leaves the intended system UI visible.
The transition from an already-open owned native picker closes it only after a
native busy response, then retries its closing animation within a one-second
bound. With access unavailable it remains open. Native codes survive helper exit
errors in private diagnostics rather than being silently discarded. Bar conceal
does not cancel a fresh, visible auxiliary pane; explicit cancel still closes it.
Bluetooth's first On/Off row is clickable and owns the sole power action. Header
and device callbacks keep separate row indices; native device argv are unchanged.

The dock renders only app icons over fully transparent pixels. It has no shelf,
blur, border, shadow, text, badges or active markers. Autohide, magnification,
one icon per application and right-click Show windows/Hide/Quit are retained;
blank transparent space passes clicks through.
Native control descriptors may include subtitle text (160 characters), a finite
0–1 meter for CPU/GPU/memory/battery, six hourly weather forecast cards beginning
next hour (start timestamp strictly after now), and six
daily cards. Daily fields are day, ISO date, high, low and condition, each at
most 16 characters. Daily dates start tomorrow in the pinned forecast timezone.
The daily strip sits directly below the hourly strip and uses the same icons;
the old day/night textual periods are omitted from native weather rows.
Each card contains hour, temperature, condition and precipitation strings of
at most 16 characters. Condition is one of clear, night, cloudy, rain, snow,
storm or fog; it maps to a fixed SF Symbol inside the helper. These fields
carry display data only and cannot select commands or arbitrary symbols.
The compiled helper accepts --controls-preview PATH [PANEL] for deterministic
nonpersonal fixtures; omission retains the CPU preview. All ten native control
panel types are supported. Dock geometry and hit rectangles remain unchanged;
its smoothing is time-based and its timer follows the target display up to 120 Hz.
The private desktop status record includes controls.backend_available, true
when a supported installed Python executable can launch native callbacks.

Graphite/Islands is the fresh-machine default, with eight-point gaps between section pills
and the connecting ribbon background off. Optional ribbon hides those spacers.
desktop theme --theme graphite|nocturne|tidal|ember|iris --layout ribbon|islands restyles existing
bar items without reloading, changing wallpaper or restarting the helper.
themes.json declares the reproducible default; private state retains local
selections across apply. The current-app control opens the nested menu-heading pane.

Clock opens a native 42-cell Sunday-first month grid with month/today navigation,
selected-day agenda, event dots and Calendars source selection. The helper
requests macOS Full Calendar Access only on an explicit connect action and only
reads EventKit events. Google authentication/sync belongs to macOS Internet
Accounts. All synced sources can be selected locally; no Google token is tracked.
Ad-hoc-signed binary updates can require renewed OS approval; theme changes do
not rebuild. Local client notifications carry only bounded action names/indices.

Weather is next to the clock and leaves notifications furthest right. The
declared ZIP97750 NWS lookup point is44.662,-119.788; no location tracking or
API credential is used. The bar shows hourly forecast temperature; hover adds
wind in mph, precipitation chance, upcoming hours and extended periods. Refresh
is explicit or on reveal when due, with private cache and stale/offline labels.

Native descriptors carry an optional pinned boolean and up to eight bounded
item-anchor rectangles (x/y/width/height). A click pins the control; a repeated
click, Escape or outside press dismisses it. Hover cannot replace a pinned
control. Request-bound private dismissal records do not contain device data.

scripts/dotfiles ai prepare validates the Apple Silicon platform, retains a
matching MLX environment or prepares the declared Python/package pins before
switching ~/.venvs/mlx with private recovery state. status verifies it without
loading a model; undo restores the original pointer/directory and refuses later
manual pointer edits. MLX_ENV overrides are preserved and must be unset before
managing the default path. No inference service or model download is started.

## Failure Semantics

Invalid arguments, unsupported preference types, directory conflicts and failed
subprocesses return nonzero. File application restores completed replacements on
a caught failure; preferences have a separate rollback. Restore rejects changed
backups or later user edits before mutating any destination. Process interruption
can leave partial state; the backup manifest remains the recovery input.

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `039e60107ac51996af39cc32e9a92e43e12cdd7c4787cdea4e3e61e368eca7b8`
- Significant implementation surfaces: `.config/` (6 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (16 files), `tests/` (9 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->

## Display pane protocol

The public bar item remains `brightness` for existing brightness_change events,
scroll adjustment and callbacks; its visible identity is Display. The signed
Desktop Panels executable accepts `--display-snapshot` or `--display-action JSON`.
Responses have sampled time, at most 32 typed native rows, at most eight connected
screens, and a Boolean handoff. Rows contain kind (toggle/device/settings), page
(display/mirroring), role, identifier, text, selected and enabled. The native helper
revalidates observed controls at action time. Python rejects responses older than
thirty seconds, malformed metadata, duplicate identifiers and unexpected controls.
Screen records contain name, width/height in pixels, main/extended/mirror mode and
an optional measured refresh rate; unknown refresh rates are omitted.

Private display-snapshot.json and literal row actions remain under the existing
0700 state directory with 0600 files. Shared native-query locking serializes Wi-Fi
and Display popups. Appearance toggles refresh the themed pane; device/settings
actions hand off to native pairing/content confirmation and close only the matching
custom request. Discovery never selects a screen or changes the display topology.
An absent or stale snapshot yields an immediate live slider and noninteractive
discovery label. The watcher waits at most three seconds for a fresh matching
`panel-ui-status.json` request/name/visible acknowledgement before native reads.
Pointer exit, a newer request or failed renderer startup cancels pending work;
late failures do not reopen a dismissed pane.

Display responses may include a Boolean `partial`. Only incomplete responses
may omit the native Settings row; malformed rows are always rejected. A failed
nearby scan is labeled unavailable, never interpreted as no nearby displays.
`panel-ui-status.json` reports `display_cover` and window `level` for verifying
actual stacking. Cover begin/end notifications carry a separate bounded token;
only a matching Display request can begin, and stale end notifications cannot
clear a newer transaction. Visible refresh is twenty seconds, not four.

`bar/native-ui-lease.json` is a 0600, request-token-owned record of PID and
expiry. The native-menu watchdog accepts only an owned private regular file,
a live PID, and expiry within twelve seconds. Display writes it atomically
after its screen covers are ready and clears only its own token during cleanup.
Native workspace self-tests cover active ownership, stale end notifications,
unsafe file mode, expiration, and a missing process.

A replacement Desktop Panels UI server reads the validated active native-UI
lease token at startup and restores temporary stacking before its first draw.
It therefore remains visible if the preceding UI process exited during a
discovery request. Malformed token, PID or expiry types are ignored. Matching
end notifications restore ordinary stacking for both original and replacement
servers; expiry remains the fallback.

`desktop overview` / `desktop-edge --overview`, Control-Up, and the custom bar
monitor item open the replacement overview. Requests use kind `overview` in the
existing private workspace protocol. Status exposes counts, switching state and
fixed error codes, never Space IDs, window titles or pixels. Escape, Close, outside
click, native Space changes and the two-minute fallback dismiss the panel. A
switch in progress survives its own Space-change notifications, and stops on
explicit dismissal. Preference manifests may include a `path` of dictionary keys;
guarded restoration owns only that scalar leaf and preserves sibling bindings.

Three-finger up/down also open/dismiss the Workspaces view. The main status
includes gesture device/recognition counts, with no touch coordinates or history.
Card drag/drop and Move to actions target connected monitor headers; Display
controls opens the existing custom sharing pane. Exact AX identity and live
screen presence are required for a move. Screen/Space changes dismiss ordinary
overviews; in-progress owned switch/move transactions retain their bounded state.
