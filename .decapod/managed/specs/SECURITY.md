# Security and state boundaries

## Data Classification

The repository tracks portable configuration, source, tests, and authored
specifications. It never tracks SSH private keys, Codex auth.json, session logs,
SQLite databases, model weights, Podman disks, cloud tokens, or runtime caches.
.codex uses an explicit tracked-file allowlist; generated local files are ignored.
Decapod runtime data and workspaces are ignored; its config, governance and
supported authored/generated specification surfaces are versioned.

Backup directories are private (0700). Copied Codex and local Git files are
0600. Backups may contain prior local configuration and remain outside Git.
Git identity/signing settings and allowed signers are machine-local. Installation
preserves existing Git identity and credential helpers by adding an include.

## Threat Model

Subprocess arguments are passed as arrays. Shell helpers quote paths; tests
cover worktree destinations with spaces. Restore rejects later edits and corrupt
backups. The installer is local-user tooling, not a security boundary against a
malicious user-controlled backup manifest or repository.

Codex's workspace sandbox, network access preference and on-request approval
policy are retained. Local-model invocation does not disable these boundaries.
mlxserve binds to loopback by default. No network service is started at login.
All container workspaces must be headless, and access to the host's credentials
is never implied merely by creating a container.

## Authentication

Git, GitHub, Apple and model-provider authentication belongs to their external
clients and local credential stores. The installer never creates accounts or
copies authentication state into tracked configuration. Future agents must ask
the user to select an Apple team when needed; no team identity is stored here.

## Authorization

Explicit install groups constrain mutation. Restore checks all targets before
writing and refuses later edits. Publication needs task authorization and current
proof. Container helpers mount only the chosen project and drop capabilities;
they do not grant access to host credentials or start machines at login.

## Desktop and inference boundaries

Calendar authentication belongs to macOS Internet Accounts. EventKit requires
Full Calendar Access on macOS 14+, requested only by explicit user action; the
helper uses read APIs and offers no event mutations. Event titles/dates/source
objects stay in memory. Only selected calendar IDs are saved in private state.
Generic native bundles contain permission purpose strings, never a personal
team, certificate or account. They are ad-hoc signed locally; binary updates
may require fresh OS consent. Dotfiles never writes TCC databases or bypasses
OS permission prompts.

The click-open current-app pane and its File/Edit/View/etc. hover submenus
require Accessibility for Desktop Controls. Actual
AX menu elements are read on a bounded background queue and retained in memory.
Enabled leaf actions are pressed once only if the same app is still foreground;
an action timeout is never automatically retried because a modal command may
already be executing. Hover only reads/opens custom menus. Disabled commands
remain disabled. Root wrapping preserves the original AX elements and order,
and expands headings without pressing them. Fresh click-time reads and submenu
responses are rejected after dismissal or foreground-PID changes. Mouse/key
event monitors dismiss open menus only; Escape is not consumed and other keys
do nothing. No menu titles or command data are committed to Git.

The Apple icon uses themed rows with fixed native actions rather than another app's AX
tree. Application launches resolve four allowlisted bundle identifiers, with
an exact installed system path fallback for About This Mac. No menu payload
supplies shell text or an arbitrary URL. Force Quit displays a Cancel-default
native chooser, retains the selected running-application object and never acts
on hover. Power/session actions run only after item selection: restart and
shutdown use kAEShowRestartDialog/kAEShowShutdownDialog, and logout uses
kAELogOut, never their immediate/forced variants. Automation consent is left to
macOS, with a generic purpose string. Screen lock uses a dynamically resolved
private login-service function; it is disabled if unsupported and is not invoked
by automated checks. This Apple-menu build changes the ad-hoc binary identity;
Calendar or Accessibility may require renewed local approval.

Native control descriptors are private bounded JSON read from one fixed path;
the helper rejects symlinks, wrong owner/mode, nonregular files and malformed
types/ranges. Descriptors contain display text and action booleans, not shell
commands. Callbacks use fixed executable/script paths and literal arguments;
Hourly and daily forecast arrays are each capped at six, text is bounded, condition names
come from an allowlist, and hardware/battery meters reject nonfinite/out-of-range
values. The weather strip reads cached declared-location data without new
network requests, account state or location permission. Deterministic preview
fixtures contain no actual calendar events, device identifiers or network names.
backend revision/panel/index checks select previously generated argv actions.
This is local-user tooling, not isolation from a compromised same-user process.

System level events select only the fixed volume/brightness read paths. Event
text does not select executable commands or settings. The private device-refresh
record contains only an event token, control name and request identifier; it
arbitrates concurrent reads without storing device details. Visibility, request
and dismissal checks run before and after device reads, so delayed events cannot
reopen a dismissed panel or replace a newer interaction. This refresh path adds
no timer or background device-reading process; its native helper API is unchanged.

Item anchors are capped at eight finite bounded rectangles; hidden/offscreen
sentinels and invalid sizes are rejected. Pinning accepts only a boolean and
native dismissal writes a request-only 0600 file with exclusive no-follow
creation and atomic replacement. A stale acknowledgement cannot dismiss a
new request. Escape/outside-click handling is local to the panel loop, without
a global event tap. This native build changes the ad-hoc identity, so prior
Calendar or Accessibility consent does not prove access for the new build.

Desktop activation is explicit. The helper uses private SkyLight menu calls,
DisplayServices brightness, login-service screen lock and a Mission Control
notification with SIP enabled;
it does not inject code, warp the pointer or require root. A scoped
CGEventTapCreateForPid filter targets only the native Dock and only mouseMoved
at the outer bottom two points while healthy, with detected Mission Control excluded.
It subscribes to no keyboard/button/drag/wheel events, excludes connected-screen
seams and detaches on restore or failed health checks. Accessibility remains a
manual OS approval; without it, the native Dock can still reveal.
An OS update may change these interfaces. Ordinary failure restores the native
menu; SIGKILL cannot run cleanup, and the owned LaunchAgent restarts the helper.
Undo recovers the menu before checking guarded preference restoration.

The native-picker fallback does not link CoreLocation/CoreWLAN, request additional
consent or contain a Location purpose string. The native picker displays its own
real network names directly on hover; that fallback does not read or retain them. Saved
profiles never stand in for availability. Bounded AX traversal uses only fixed
status-item and wifi-header identifiers to open idempotently and close only the
Wi-Fi panel. Passwords are neither read nor passed. SystemConfiguration emits a
fixed change event without reading, storing or forwarding network values.
Location remains off. The failed custom scanner was removed rather than
requesting permission again or changing TCC. The separate cached Wi-Fi Access
builds from the rejected experiment may remain in private local state for
recovery, but their active symlink and config link are removed and no service
launches them. Existing Desktop Controls identity/Calendar/AX consent are intact.

The new Desktop Panels adapter is distinct from that removed scanner. It links
ScreenCaptureKit and AX, never CoreLocation/CoreWLAN. Its own Accessibility and
Screen Recording approvals are requested only by an explicit command, never
hover. Native AX controls provide names and selection; saved profiles do not
substitute for nearby availability. Bounded traversal skips text/secure fields.
Screen snapshots exist only in memory for native-popup concealment; production
writes no screenshot or video. Fresh control descriptors and throughput samples
remain in private local state, not Git. Literal descriptors are JSON/argv data,
never shell commands; selected state is rechecked before an action. The single
display/macOS version boundary falls back to Apple's picker. Signing identities
are selected from local Keychain or environment and never written to the repo.
Normal registered-app Wi-Fi activation, real fullscreen hover, rates and native
disclosure interaction are verified with both explicit OS approvals. Authentication
handoff remains unverified without changing the owner's connection.
Request-bound mouse passthrough is acknowledged before native actions, resumed
in cleanup and reset by an eight-second watchdog. It never grants a permission.
Diagnostic-host tests use the agent's existing approvals and do not
grant or inherit permissions into Desktop Panels. Fixed-code diagnostics contain
only stage, time and known access booleans; arbitrary native error text is
discarded so network names cannot enter error reports. Separate stage records
prevent later status checks from erasing the snapshot failure. These records and
the actual network snapshots remain private local state, never repository files.

Window metadata is limited to application ownership, count and geometry;
screen recording and private window titles are not needed. Device names,
addresses, samples, logs, compiled helpers and wallpaper archives remain in
0700 local state with 0600 records. Device actions pass argv arrays. Native
quick panels require local Accessibility/Automation; dotfiles cannot approve
them. LuLu is installed but its extension/filter needs separate local approval;
installation is not evidence of an active firewall.

Weather sends only the explicitly configured forecast point to the official
HTTPS NWS API with a public application User-Agent. Advertised forecast links
are checked against the NWS host. No GPS, user account or API key is accessed.
Forecast caches and refresh locks stay in private runtime state; network reads
are bounded and never performed synchronously by hover rendering.

MLX preparation verifies the new environment before activation, preserves the
old directory/link, and refuses later pointer edits. Environment/model stores
and manifests stay outside Git. Neither this operation nor shell initialization
loads a model. Ollama remains manually started and is not enabled at login.

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `53759c6499c5cbd224f07d2c14267eb91880ee3a875c5a979778d926055448cd`
- Significant implementation surfaces: `.config/` (5 files), `.github/` (2 files), `README.md/` (1 files), `scripts/` (10 files), `tests/` (7 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
