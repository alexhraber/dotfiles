# alexhraber/dotfiles

A reproducible engineering workstation: Ghostty, Tokyo Night Storm,
JetBrainsMono Nerd Font, Starship, zsh, tmux, polyglot Neovim, Git, Codex,
local AI, infrastructure tools, and reversible macOS preferences. Podman is
the intended container runtime; Decapod is initialized for isolated workspaces.
The optional desktop profile adds an autohiding SketchyBar and a native,
open-apps-only dock, inspired by the purple/cyan glass panels in
[alexhraber/nixos](https://github.com/alexhraber/nixos).

The target workstation is an Apple M1 Max MacBook Pro. All authored configuration
and automation live in `~/src/dotfiles`; installed shell/editor configuration
links to the main checkout. Mutable Codex preferences are copied deliberately.
Homebrew installs native Apple-silicon tools. Credentials, model stores, VM disks,
application state and private backup manifests stay outside Git.

Treat changes as infrastructure as code: edit a declared dependency or config,
inspect `./install.sh --all --deps --dry-run`, run `scripts/check`, apply,
then run `scripts/dotfiles doctor --all` and the
relevant integration check. Repeated apply converges to the declared state;
doctor detects configuration drift. The `macos` group and explicit desktop
lifecycle change user defaults with per-key backups. Package versions are moving releases, so reproducibility here
means declared tools and preferences, not byte-identical system images.

## Install

Homebrew and Python 3 are needed to bootstrap. The dependency installer adds
Python 3.14 for configuration validation. Inspect `Brewfile` and `install.sh`
before applying a new checkout.

```sh
./install.sh --dry-run --deps       # Preview the default terminal group
./install.sh --deps                 # Install tools and terminal/editor config
./install.sh --all --deps           # Full workstation, including macOS preferences
exec zsh -l
```

Select any combination with `--groups terminal,git`. The default stays
`terminal`; `--all` explicitly selects every group:

| Group | Managed setup |
| --- | --- |
| terminal | Ghostty, shell, tmux, editor, navigation and terminal tools |
| git | Portable Git settings, delta, global OS/editor ignore file |
| codex | Codex app, portable CLI preferences and instructions |
| workspace | Podman and the explicit `cws` container helper |
| dev | GitHub CLI, jq/yq, uv, Cargo binary installer, linters, language servers, native build tools, FFmpeg, sccache, hyperfine and Apple Silicon macmon |
| reverse | Ghidra and its Homebrew-managed JDK for REA native analysis |
| apple | Mac App Store CLI for the explicit, interactive Xcode setup script |
| infra | kubectl, Helm, k9s, OpenTofu and grpcurl |
| ai | Ollama and native MLX on Apple silicon |
| apps | Google Chrome |
| desktop | SketchyBar, JankyBorders, initially disabled AeroSpace trial, LuLu, Bluetooth/audio controls and Apple Silicon telemetry |
| macos | Finder, keyboard, text input, Dock and screenshot preferences |

Dependency installation uses a curated Brewfile
and `--no-upgrade`; it does not remove unrelated packages. Podman is installed
by the workspace group. Rust and Decapod remain managed by your existing rustup
and Cargo installation. The Brewfile tracks direct tools, not their transitive
libraries. An existing manually installed Chrome is retained; a missing Chrome
is installed through its cask. Existing Homebrew-managed Chrome remains in the
bundle. This avoids administrator-password requirements during app adoption;
the installer never uses `--force` or deletes browser profiles. Node and TypeScript are
Homebrew dependencies of language servers. Application runtime versions belong
in projects using mise, uv or rustup.

The dev group copies `.config/mise/config.toml` with the same backup/restore
rules as other configuration. It selects Node 24.18.0 and npm 11.16.0, matching
REA's development pins, and enables project `.nvmrc`/`.node-version` and
`packageManager` selection. Existing mise activation in zsh switches versions
when entering projects. Install the declared runtimes explicitly with
`mise install`; a shell does not install them. See [mise's Node documentation](https://mise.jdx.dev/lang/node.html).
Rust remains under rustup: the current Decapod checkout needs
`rustup toolchain install 1.96.1 --profile minimal --component rustfmt,clippy,rust-analyzer`.

For REA's Ghidra backend, install `--groups reverse --deps`. A copied shell
helper discovers Homebrew Ghidra and JDK 21 through `HOMEBREW_PREFIX`, preserving
explicit `GHIDRA_INSTALL_DIR` and `JAVA_HOME` choices. Its source line is added
to `.zshrc.local` with backup/restore and without replacing other local settings.
The engine is headless unless explicitly launched; the
installer does not register an MCP server or change agent authentication.

The dev group also copies the generic Cargo configuration to
`~/.cargo/config.toml`, backing up any previous file. It enables local compiler
caching with [sccache](https://github.com/mozilla/sccache); project Cargo settings
and `RUSTC_WRAPPER` can override it. Incremental compilation remains enabled for
development: eligible dependency and release-library compilations are cached,
while link steps and incremental compilations are not. Inspect usage with
`sccache --show-stats`; stop its on-demand server with `sccache --stop-server`.
No cache server is registered at login, and cache contents stay outside Git.

Run `macmon` for on-demand Apple Silicon CPU/GPU/ANE power, temperature and
memory telemetry, or `btop` for processes. Quit when finished. The installer
does not enable macmon's HTTP server or service. Use
`hyperfine --warmup 2 'your-command'` for repeated timing measurements; it runs
the supplied command repeatedly, so choose a command safe to repeat.

Full Xcode and its iOS SDK are required for Scripture's simulator/device builds.
Run `scripts/setup-xcode` in a visible terminal after installing the apple group.
It installs Apple's Xcode through `mas`, selects the toolchain, presents the
license for local review, runs first-launch setup and downloads the iOS platform.
Mac administrator and App Store authentication happen locally. Then sign in to
Xcode Settings > Accounts for Personal Team development signing. Certificates,
provisioning profiles, Team IDs and signing keys remain outside Git. Command
Line Tools alone provide Swift and macOS compilation, without iOS builds.

Apple development team selection is deliberately not saved here. A future agent
must ask which team to use when signing is needed, then populate only local
project settings or command-line overrides. Do not commit team names, Team IDs,
Xcode account preferences, private signing projects or provisioning assets.

Use the scripts directly; no task runner is required. Preview with
`./install.sh --all --deps --dry-run`, apply with `./install.sh --all --deps`,
check with `scripts/check`, and inspect the installation with
`scripts/dotfiles doctor --all`. `brew bundle check --no-upgrade --file=Brewfile`
checks declared packages; `brew outdated` reports updates without applying them.
Homebrew packages are current releases, not version-pinned; Neovim plugins
are pinned separately.

The installer validates destinations before changing files, saves every
conflicting file or symlink in a private backup directory, and writes a JSON
manifest. Repeated installs make no configuration changes when files already
match. Ghostty's XDG and macOS application-support config locations are both
managed so they cannot accidentally disagree. Configuration installation starts
no services. The explicit desktop runtime command below enables its LaunchAgent
and desktop services; Ollama remains manually started.

Backups default to `~/.local/state/dotfiles/backups/`; the exact manifest path
is printed after installation. Restore configuration with:

```sh
./install.sh --restore /path/to/manifest.json --dry-run
./install.sh --restore /path/to/manifest.json
```

Restore checks all targets and backups first and refuses to overwrite later
edits. It restores original symlinks as symlinks; `.resolved-content` files also
preserve their original contents. Restoration does not undo repository updates,
package installations, plugin downloads, or runtime caches. Existing directories
are never replaced. `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, and `CODEX_HOME` are
respected when set.

## macOS preferences

`.config/macos/preferences.json` shows file extensions, Finder path/status bars
and searches the current folder; enables fast key repeat; disables smart quotes,
dashes, automatic periods and spelling correction; hides recent apps in the Dock;
and stores PNG screenshots in `~/Pictures/Screenshots`.

The macOS group also uses Finder list view and a compact, auto-hiding Dock with
windows minimized into their application icons, and disables automatic Space
reordering. It backs up only changed keys,
preserving boolean, integer, floating-point and string types and absent keys,
then applies and reads each key back. A failed application rolls back preference
changes. Its separate private manifest uses the same `--restore` command and
refuses to overwrite later edits. File installation and preferences are separate
transactions. The screenshot directory and contents remain during restore.
On Linux, the macOS group is skipped.

Existing apps may need reopening or logout before consuming the preferences;
the installer does not restart Finder or Dock. Apple documents
[Finder settings](https://support.apple.com/guide/mac-help/change-finder-settings-on-mac-mchlp2803/mac)
and [key repeat](https://support.apple.com/en-gb/guide/mac-help/mchl0311bdb4/mac).
CLI keys are verified on the installed macOS version, not treated as a stable
cross-version API. Security controls, cloud accounts, keychains, accessibility
permissions and browser profiles remain locally managed.

## Workstation design

The desktop follows the fullscreen workflow: content fills the screen, and
controls appear at the edges only when needed. Tokyo Night Storm grounds the
terminal and editor; the desktop defaults to Nocturne charcoal, violet and cyan.
Three alternate palettes remain available. Tidal
pairs deep petrol with seafoam and brass; Ember uses warm charcoal, copper and
rose; Iris combines plum, lavender and mint. SF Pro gives system controls a native feel, while monospaced
text is reserved for code and telemetry. The unbranded
wallpaper keeps most of the screen quiet.

The default islands layout separates hardware, connections, battery, clock/weather and
notifications into individual pills, with an eight-point empty gap between
sections and no connecting background. Application context stays at the left;
notifications sit furthest right. The optional ribbon layout joins the right
sections into one capsule and hides the gap items.
Hardware uses distinct processor, graphics and memory icons, with compact
CPU/GPU utilization percentages and used memory beside them. Temperatures in
Fahrenheit, power, capacity and swap details stay in the hover panels. Fixed value widths prevent sampling from
shifting neighboring controls. Sound and display use icons alone.
Hover reveals cached controls after a short intentional dwell, then refreshes their data. The dock
shows one icon per open application on a fully transparent background. Its
fisheye layout moves neighboring icons so magnification stays usable.
The bar reveals at a fixed position, so controls do not slide away from the
pointer. Hover requests cancel on exit, panel switches commit together, and
repeated hover keeps the current panel open. A short bridge grace period lets
the pointer reach native rows, graphs and sliders. Reduce Motion is respected
for dock animation. Bar IPC runs away from the animation thread, and
dock animation stops while hidden.

The same restraint applies below the UI. Native development tools and sccache
serve the Rust/web/Apple/reverse-engineering workload. Models and containers
consume resources on demand. Ollama is manual; MLX has an explicit pinned
prepare/verify/undo lifecycle. AeroSpace and borders are optional experiments,
leaving native fullscreen Spaces as the default. Changes are declared here,
backed up locally and verified before publication.

## Desktop profile

Install configuration and dependencies, then explicitly enable the desktop:

```sh
./install.sh --groups desktop,macos --deps
scripts/dotfiles desktop apply
scripts/dotfiles desktop status
scripts/dotfiles desktop permissions
scripts/dotfiles desktop theme --theme nocturne --layout islands
scripts/dotfiles desktop undo
```

The native fullscreen workflow remains intact. Reveal the status bar at the
top three pixels and the dock in the bottom-center 44-point icon footprint.
The dock icons sit at the screen's bottom edge. Each hides after
leaving it for 320 ms; hovering a bar control opens its cached panel. Popups remain
usable while the pointer is inside them. There is no permanently reserved
strip, extra native menu row, or dock divider.

| Control | Hover / interaction |
| --- | --- |
| Apple | Real Apple menu commands, in the custom style |
| Active app / File / Edit / View / … | The active application's actual menu commands, disabled states, shortcuts and submenus |
| Clock | Current macOS time; native month grid, date selection, previous/next month, today and synced calendar agenda |
| Weather | ZIP 97750 forecast, wind in mph, precipitation chance, upcoming hours and extended outlook |
| Sound | Volume slider, mute, output selection; scroll the bar item for volume |
| Display | Built-in brightness slider; scroll the bar item to adjust |
| Wi-Fi | Power toggle and connection details; native quick panel for network selection |
| Bluetooth | Power toggle and paired-device connect/disconnect |
| CPU / GPU | Load graph, real average die temperature in °F, power and fans |
| RAM | Usage graph, capacity and swap details |
| Battery | Charge, charging state, time estimate, temperature and cycles |
| Notifications | Furthest right; Notification Center, Focus and hardware alerts |

The hardware icons replace CPU / GPU / RAM words in the main bar; panel headings
retain descriptive names. `G` beside the memory icon means used GiB; full capacity
and swap stay in the panel, with swap warnings retained. Panel surfaces are opaque
and blur-free for predictable rendering and readability.

Common controls work in the popovers instead of launching Settings. Native
Wi-Fi, notification and Focus quick panels and App Exposé require local
Accessibility/Automation approval for the responsible SketchyBar/osascript
process. Bluetooth may request macOS Bluetooth permission. Approval is a local
OS action and is not captured or bypassed by dotfiles. Network names can be
redacted without Location permission; private network/device names are never
stored in Git. Hardware alerts do not count unread app notifications: macOS
offers no supported API for reading all other apps' notification content.

Nocturne uses charcoal surfaces, readable violet accents and cyan hardware
icons, inspired by the owner's NixOS Waybar. From the far right inward, the
order is notifications, clock, weather, then battery, controls and hardware.
Eight-point gaps separate the section pills; the outer bar is transparent.
The left side holds the Apple logo, active app and its actual menu headings.

Use `desktop theme --theme nocturne|tidal|ember|iris --layout islands|ribbon`
to change the live appearance. The dock always renders only application artwork,
independent of the bar theme. Text/control contrast is checked against the declared surfaces.
`themes.json` declares the fresh-machine default; local selections stay in
private state and survive apply. `desktop theme` changes only appearance,
without resetting wallpaper or desktop preferences.

All hover controls use native AppKit panels with SF Symbol headings, large
current readings, a violet accent rule and cyan detail graphs. CPU, GPU, memory
and battery use capacity meters and two-column detail cards. Sound and display
use accent-colored native sliders; hardware graphs show a 0–100% scale and latest
sample, share a bounded private history and refresh while open. Weather adds six
cached hourly cards with conditions, Fahrenheit temperatures and precipitation
chance above the extended outlook. Device actions have distinct hover targets
and connected-device indicators; longer panels scroll without a second background.
Native pointer geometry keeps panels open through the anchor-to-panel crossing.
Late refreshes cannot reopen a dismissed request or replace a newer panel.
Native actions select the installed versioned Homebrew Python first, with Intel
Homebrew and system-Python fallbacks; a missing unversioned `python3` link does
not silently disable buttons. Desktop status reports backend availability.
Deterministic, account-free native previews are available through the compiled
helper: `desktop-edge --controls-preview /tmp/panel.png weather` (or `cpu`, `gpu`,
`memory`, `battery`, `volume`, `brightness`, `wifi`, `bluetooth`, `alerts`).

Calendar uses EventKit on macOS 14 or later. Add Google in **System Settings →
Internet Accounts**, enable Calendars, then use the clock's **Allow calendar
access** button. The agenda reads the calendars already synced to this Mac;
**Calendars…** chooses which sources are shown. macOS calls this Full Calendar
Access; this helper only reads events and provides no event editing. Event titles
remain in memory, and calendar selections stay in private local state.

The clock reads the macOS system clock every second, including while hidden,
and refreshes on bar reveal and wake. Seconds stay hidden; its compact fixed-width readout does not
shift adjacent controls. Time synchronization stays with macOS; no separate NTP
client, network stream or clock daemon is installed.

Apple/app menus require Accessibility approval for **Desktop Controls**.
Hover the Apple logo and choose **Enable Accessibility…** if needed. The helper
reads the active app's Accessibility menu tree and presses the selected real
command exactly once. Disabled items remain disabled, and a changed foreground
app invalidates a pending command. Apps that do not expose a menu through
Accessibility show an unavailable state. No replacement desktop shortcuts are
installed. Submenus open on hover; native shortcut labels are informational.

The native helper is built atomically as a locally ad-hoc-signed app bundle;
failed builds cannot replace its active link. It embeds generic permission
descriptions and no personal signing team. macOS can request approval again
after a native binary update because an ad-hoc signature is specific to that
build. Palette/layout changes do not rebuild it. OS consent is never bypassed.

Weather is fixed to ZIP **97750**, using the point returned by the
[NWS ZIP lookup](https://forecast.weather.gov/zipcity.php?inputstring=97750)
(44.662, -119.788 in the Mitchell area). `.config/sketchybar/weather.json`
declares this location; it never follows the machine or requests Location access.
The bar temperature is the current hourly forecast in °F. Hover shows wind in
mph, precipitation chances and the extended forecast from the
[National Weather Service API](https://www.weather.gov/documentation/services-web-api).
Refresh is bounded, cached for 15 minutes and backed off after failures. Hover
reads local cache immediately; an old forecast is marked cached rather than
presented as fresh. Runtime data stays outside Git. No API key is needed.

The dock is a small AppKit panel compiled from `scripts/desktop-edge.m`: open
apps only, stable ordering and hover magnification. Resting icons stay at 40 points;
peak hover size is 77.5 points, 25% larger than the previous 62-point peak
(crowded displays scale the group to fit). Its background is entirely
transparent: no glass, shelf, border, shadow, labels, badges or active markers.
Click an icon to activate it; right-click for Show windows / Hide / Quit.
Empty transparent regions pass clicks through to the application underneath.
Magnification uses elapsed-time smoothing at up to the display's native 120 Hz,
settles exactly, and avoids animation redraws once stationary. Reduce Motion
snaps both zoom and horizontal tracking to their targets.
Finder appears only when it has a window. Window counts use public WindowServer
metadata; they do not scrape titles or require screen recording. There are no
pinned apps, separator, Trash, or new desktop-navigation bindings.

The same native helper observes pointer position without an event tap or cursor
warping. It checks SketchyBar health before suppressing the native menu, restores
the native menu when stopped or when SketchyBar is unavailable, and is restarted
by a user LaunchAgent. Menu suppression uses the reversible private SkyLight
calls used by [yabai](https://github.com/asmvik/yabai); SIP remains enabled.
macOS updates can change private interfaces, so recheck after an OS upgrade.
Built-in brightness uses DisplayServices get/set, following the Apple Silicon
implementation in [brightness](https://github.com/nriley/brightness/blob/master/brightness.c).
It does not change external-display brightness. Mission Control temporarily
suppresses the custom surfaces while the native overview is open.
The native Dock is kept alive for Mission Control and Spaces; its presentation
uses auto-hide with a long delay while the replacement is active. The setup
restarts Dock after changing those preferences, without changing pinned apps.

The profile snapshots the original per-display wallpaper/options, typed menu
and Dock preferences, and loaded desktop services into
`~/.local/state/dotfiles/desktop/` (or `XDG_STATE_HOME`). Reapply retains this
original baseline. Undo restores it, stops only services enabled by the profile,
and removes its LaunchAgent. Later edits to managed preferences block their
restoration; native menu recovery happens first. Configuration links and installed
packages are retained; use the installer's printed manifests to restore files.
If a newer wallpaper was chosen manually, save that choice before undo, which
restores the captured wallpaper on matching connected displays.

The wallpaper's authored SVG and exported PNG live in `assets/wallpapers/`.
The bar and border configuration live under `.config/sketchybar/` and
`.config/borders/`; compilation products, telemetry, device state, logs,
LaunchAgents and wallpaper backups stay outside Git. Native compiles run in
macOS CI; portable lifecycle and control tests also run on Linux.
Only SketchyBar and the native edge helper start with the enabled profile.
JankyBorders is available for an optional windowed-workflow trial and stays
stopped by default: fullscreen windows do not benefit from an extra border daemon.

macOS requires at least one regular Desktop even when all other Spaces are
fullscreen apps. This setup does not destroy that required Space or move your
fullscreen apps. Keep the spare Desktop at the far right and use the trackpad.
Command+number is not mapped to ordinary Desktop shortcuts, which would not
target fullscreen Spaces. No Alt/Control-number substitutes are installed.
AeroSpace is installed for an explicit trial, starts disabled, and has no login
startup or workspace navigation bindings. Launch it manually and use
`aerospace enable on` to try tiling; `aerospace enable off` pauses it.

LuLu is installed as the outbound firewall option. Launch it once and approve
its macOS system extension and network filter locally. Rules and approvals are
machine state and remain outside this repository. Installation alone does not
mean the firewall filter is active.

## Shell and projects

Login and non-login interactive zsh share `.config/zsh/env.zsh`. It detects the
Homebrew prefix, adds local tools, and sources `~/.cargo/env` when available.
Mise can put its project shims ahead of these paths. Plugins are registered once
per shell; `src` starts a fresh login shell to reload changes. Optional local
settings go in `~/.zshrc.local` and remain outside Git.

- `proj`: fuzzy-pick a directory under `~/src` (override with `PROJECTS_DIR`).
- `wt`: fuzzy-pick a Git worktree of the current repository.
- `wtnew <new-branch> <directory>`: create a worktree and enter it.
- `v`, `vi`: Neovim when installed, with a system-editor fallback.
- `lg`: Lazygit; `gs`, `gd`, `gds`, `gl`: common Git views.
- `dotfiles doctor --all`: inspect the installed configuration and dependencies.
- `tm`: create or attach the `main` tmux session; Ctrl-b remains the prefix.
- `cws <image> [command ...]`: run in the current project through Podman.

Modern command aliases are enabled only when their tools exist. `grep` keeps its
standard behavior; invoke `rg` directly. Fastfetch runs in interactive login
terminals; set `FASTFETCH_DISABLE=1` to skip it. Ghostty retains its standard
split, tab, zoom, and reload shortcuts.

The rice uses a steady block cursor, subtle Ghostty translucency, matching fzf
colors, file previews on Ctrl-T and directory previews on Alt-C. Ctrl-/ toggles
the preview. Starship hides local account/hostname noise, keeps SSH identity,
and shows project runtimes, bounded Git branch names, command duration and time.
Tmux uses a top status bar and pane labels: Ctrl-b then h/j/k/l selects a pane,
Shift-h/j/k/l resizes it, Tab returns to the previous window, and | / - split.

## Neovim

The configuration requires Neovim 0.12+. Native `vim.pack` installs two plugins
from HTTPS on first startup: Tokyo Night and mini.nvim. Both are pinned to
specific commits in `.config/nvim/init.lua`. No additional language runtimes
are installed when opening files. Plugin checkouts and the generated package
lockfile stay in Neovim's local directories.

Use Space as the leader:

| Keys | Action |
| --- | --- |
| Space ff / fg / fb / fh | Find files, live text search, buffers, help |
| Space e | File explorer |
| Space gs | Pick Git hunks |
| Space w / q | Save / open quickfix |
| Ctrl h / j / k / l | Move between splits |
| gd / gr / K | Definition, references, hover with an attached language server |
| Space rn / ca / cf | Rename, code action, format with an attached server |

Persistent undo, completion, surrounding pairs, Git diff signs, and a statusline
are enabled. The dev group supplies Basedpyright/Ruff for Python, TypeScript
7's native LSP for JS/TS/React, Bash language server, Lua language server and
Taplo for TOML. Python prefers the project's `.venv`; Ruff owns formatting and
import actions while Basedpyright supplies types and navigation. Space cd shows
line diagnostics; Space cq sends diagnostics to quickfix. Servers are enabled
only when their binaries are available. Projects with a local pre-7 TypeScript
installation use the legacy language-server wrapper and their own tsserver.
Deno projects are left to local configuration. Neovim supports project EditorConfig.

Rust LSP uses `rust-analyzer` from the existing Rust toolchain;
install that component with `rustup component add rust-analyzer`. Optional
language-server configuration and local settings belong in
`~/.config/nvim/local.lua` (or the equivalent XDG path).

Neovim opens a centered workbench with file search, project search and recent
files. Space ss reopens it; [b / ]b switches buffers. A tabline, static indent
guides and rounded floating windows use the same pinned mini.nvim package.

Tokyo Night Storm is shared by Ghostty, Neovim, Starship, bat, delta, and Lazygit.
The installer builds bat's theme cache. Its vendored theme is attributed and
licensed in `.config/bat/themes/NOTICE` and `LICENSE`.

## Git and signing

The Git group adds an include to your existing `~/.gitconfig`, preserving
identity, credential helpers, and other settings. Portable behavior lives in
`.gitconfig`; machine-specific overrides live in `~/.gitconfig.local`.

Pulls require a fast-forward; new branch pushes set their upstream; rerere
remembers conflict resolutions without automatically staging them. The global
ignore uses Git's native XDG location and covers OS/editor debris; project build
artifacts belong in project ignores. Existing custom `core.excludesFile` overrides
remain local. GitHub CLI authentication requires an explicit `gh auth login` and
stays outside the repository; SSH Git authentication and signing are independent.

Configure an identity and SSH signing explicitly, using a **public** key:

```sh
./install.sh --groups git \
  --git-name 'Your Name' \
  --git-email 'your-email@example.com' \
  --signing-key "$HOME/.ssh/id_ed25519_github.pub"
```

The local signing configuration and allowed-signers file are backed up before
changes. Key material is never copied into this repository. The matching private
key must be available locally or through an SSH agent, and GitHub needs the
public key registered for signing as well as authentication.

## Codex

Only portable preferences, concise global instructions, and CLI profile files
are tracked. Installation copies them to Codex home with mode 0600, so app edits
cannot write credentials or machine settings back into the repository. A later
explicit Codex reinstall backs up local changes and reapplies the tracked files.
Authentication, sessions, databases, caches, downloaded plugins, and accumulated
approval rules remain local.

```sh
codex                         # Existing model preference, high effort
codex --profile quick         # Medium effort
codex --profile deep-review   # Extra-high effort
```

Profile files use top-level keys, following the current
[Codex profile format](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles).
Global `AGENTS.md` contains working preferences; repository instructions remain
specific to each project. Approval and sandbox boundaries are preserved.

## Existing local models

Ollama stays off until explicitly started. Run `aiup` in a terminal, use
Ollama clients in another terminal, then press Ctrl-C in the server terminal
when finished. The helper runs `ollama serve` in the foreground, preloads no
model, and defaults to unloading models after each response with
`OLLAMA_KEEP_ALIVE=0`. It also enables Flash Attention and the `q8_0` KV cache.
Clients can override the unload default with an explicit `keep_alive` request.
See the [Ollama memory settings](https://docs.ollama.com/faq#how-do-i-keep-a-model-loaded-in-memory-or-make-it-unload-immediately).

For an existing Homebrew service, `brew services stop ollama` stops it and
unregisters login startup. Avoid `brew services start ollama` for this manual
workflow, since it registers login startup. The installer never enables it.

`cxlocal` starts Codex explicitly with Ollama and the already-installed
`qwen3-coder:30b` model. Set `CODEX_LOCAL_MODEL` to choose another local model.
It preserves approval and sandbox settings; ordinary `codex` keeps the cloud
model preference. Ollama's service and model files remain locally managed.

`mlx`, `mlxchat`, and `mlxserve` use the existing `~/.venvs/mlx` environment
without changing the shell's Python. Override its location with `MLX_ENV`.
`mlxserve` binds to loopback unless explicitly overridden. These commands do
not run during shell startup or automatically download models.

The Brewfile includes native MLX. Python MLX-LM uses the pinned Apple-silicon
Python 3.12 requirements in `requirements/mlx.txt`:

```sh
scripts/dotfiles ai prepare
scripts/dotfiles ai status
scripts/dotfiles ai undo
```

Prepare retains an already matching environment. Otherwise it creates a
versioned environment at its permanent path, syncs the declared packages,
verifies Python 3.12 and native Metal, then switches `~/.venvs/mlx`. A private
manifest preserves the original directory or symlink for guarded undo; later
manual pointer edits block replacement. Prepared environments and model caches
are retained on undo. No model is loaded or downloaded. The regular installer
does not prepare environments or change GPU memory limits. Regenerate the lock on an
Apple-silicon Mac with `uv pip compile requirements/mlx.in --python 3.12 --output-file requirements/mlx.txt --no-header`.

## Podman and Decapod

On macOS, Podman runs containers inside a Linux VM. The installer installs the
CLI; VM creation and startup are explicit operations:

```sh
podman machine list
podman machine init --cpus=4 --memory=4096 --disk-size=100 dotfiles
podman machine start --quiet --no-info dotfiles
podman info
```

Use an existing machine when one is already configured. VM disks, SSH keys,
connections, sessions, and container state remain local. No login service is
installed. Start the VM before using container workspaces. All VM starts must be headless;
do not enable Podman debug logging on macOS, since it adds the vfkit GUI.

`cws` checks an already-running engine and never starts a machine. Supply a
fully qualified image, preferably pinned by digest, and an optional command.
It shares only the current project at `/workspace`, uses `keep-id`, drops Linux
capabilities, blocks privilege escalation, and allocates a TTY only interactively.
Source is writable from the container. SELinux labeling is disabled for this
invocation to support shared macOS filesystems. Host auth directories, SSH agents, engine
sockets and home directories are not mounted. It refuses to mount home or `/`.
It is a development helper, not a security boundary for untrusted project code.

This repository is initialized with Decapod's local backend and container
isolation. Follow `AGENTS.md` and `decapod docs ingest` for its session, task,
workspace, and validation lifecycle. Podman is the intended local runtime.
The authored specifications under `.decapod/managed/specs/` describe this
repository; runtime state is ignored. Decapod initialization by itself does not
prove that repository checks or publication readiness passed. The supported
`repo.pr-readiness.v1` profile runs the same portable checks through
`scripts/check.py` in the verification image, using reviewed source/command
digests and an explicitly declared tool directory. The Bash entrypoint and CI
delegate to that same check owner. This proves repository-local execution;
GitHub's Linux/macOS jobs and host editor/model checks remain separate evidence.
All VM startup must remain headless; see [the upstream startup issue](https://github.com/DecapodLabs/decapod/issues/1417).

## Verification

```sh
scripts/check                  # ShellCheck, zsh syntax, and isolated tests
scripts/dotfiles doctor --all   # Dependencies and installed configuration
python3.14 scripts/editor_check.py  # Real installed language servers and formatting
```

The tests exercise scoped installation, backups, rollback on failure, repeated
installation, restoration, refusal to overwrite later edits, preservation of Git
identity and Codex state, worktree paths with spaces, shell hook behavior,
typed preference backup/restore and failure rollback, and container arguments
with a fake engine that proves no automatic VM startup occurs.
GitHub Actions runs the same suite on Linux and macOS. Config and package checks
on the actual Mac are separate from the portable test suite.
