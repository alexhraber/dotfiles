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
[b and ]b switch buffers. The default theme is Tokyo Night Storm throughout.

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
LaunchAgent and SketchyBar events; it introduces no network API.

## Desktop and inference lifecycle

scripts/dotfiles desktop apply explicitly starts SketchyBar and the native
edge helper, sets backed-up menu/Dock defaults and wallpaper, then requires
fresh PID-bound health. status reports runtime health. permissions probes
Accessibility from SketchyBar's context and opens local macOS approval settings
if unavailable. undo restores the native menu first, then guarded preferences,
wallpaper and prior service state. It retains configuration and packages.

The top three pixels reveal the bar; the bottom-center resting icon footprint
(44 points tall) reveals the dock after an 80 ms dwell. Icons grow upward from
the screen bottom, with no 26-point gap to chase. Resting size stays 40 points;
unconstrained peak hover size is 77.5 points, 25% above the previous 62 points.
Crowded layouts scale to fit. Exit hysteresis is 320 ms. Hover controls
include calendar, sound/output/mute, built-in brightness, Wi-Fi power/details,
paired Bluetooth devices, battery and Fahrenheit CPU/GPU telemetry. Notifications
are furthest right; hardware warnings are not an unread notification count.
From that right edge inward, clock and weather come immediately after
notifications. The Apple logo and actual foreground-app menu headings occupy
the left. Hover reads real menu contents; clicking enabled leaf commands uses
AXPress, with submenus, disabled states and shortcut labels retained. This
requires Desktop Controls Accessibility approval. No app-menu data is persisted.
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
selections across apply. The current-app control now opens its real app menu.

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

- Repository signal fingerprint: `91499f5aa1fd514d566d20a2035f6536e27bd313f811bfce537728e375048e47`
- Significant implementation surfaces: `.config/` (4 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (10 files), `tests/` (6 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
