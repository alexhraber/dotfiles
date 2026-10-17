# Validation

## Proof Surfaces

The external-level correction passes 86 host tests, including native compilation
and self-tests. New regressions cover hovered and pinned sliders, hidden/stale/
dismissed panes, the first key before the next native status sample, transient
read failures, and out-of-order events or a pane closing during a read. Actual
OS brightness and volume changes updated the existing unpinned hover session
through SketchyBar events; inspected native captures show the new value and
thumb. The original levels and pointer were restored. Private proof artifacts
remain outside Git; canonical validation and hosted checks gate publication.

All 87 host tests pass, including a shell event regression proving that Apple
and the app-name control open native menus only on click. Native menu compilation
passes with warnings as errors. Nested app-menu self-tests cover the two-index command allowlist, preserving
the app menu and all other headings in order while excluding Apple, empty
menu trees and inventories larger than the previous flat-slot capacity. Real
AX hover behavior still requires final-build OS consent and installed proof.
On the final installed helper, the app-name click opens the permission pane
directly under the custom bar; hover does not open it, leaving the pointer
outside keeps it open, and a second click closes it. The bar inventory contains
no standalone application headings. Fresh helper health and Calendar access
were confirmed. Real app commands and hover contents remain unverified while
macOS reports Accessibility off. The final live slider check also passes and
restores brightness, volume and mute state.

The Apple menu's native self-tests cover its fixed entries/application targets
and confirm that restart/shutdown/logout map to the OS confirmation events,
excluding immediate/forced variants. Host native compilation passes with
warnings as errors. A real AppKit menu preview was captured and inspected;
About This Mac and System Settings launches succeeded through their fixed
native targets. The installed lock symbol is present, but automated verification
does not lock, sleep, restart, shut down, log out or force-terminate an app.
The final installed helper must be checked for fresh health and calendar access
separately because the Apple feature changes its ad-hoc identity.

The next-hour correction is covered at mid-hour, exactly on the hour and across
midnight with explicit-offset timestamps. Expired and in-progress periods are
excluded from the six-card hourly strip, invalid starts do not consume its
capacity, and missing future hours never fall back to relabeling the current
hour. Separate assertions retain the current temperature in the bar/header.
The sequential-hour fixture models actual forecast windows; all 80 host tests
and native compiler/self-tests pass. This Python-only change leaves the native
helper bytes and its local permission identity unchanged.

The current composition pass adds six future-day cached forecast regressions,
Mitchell-local date boundaries, daytime icons with night lows and fourteen-period
retention. Native weather rows are checked to omit the old Tonight/day/night
list. Daily and hourly tiles share the native weatherSymbol mapping. The host
suite has 78 tests; native warnings-as-errors compilation, pure placement and
payload/pin self-tests and ten deterministic panel previews passed. Real ZIP
97750 data returned six hours and six tomorrow-onward daily cards. The new
healthy Graphite process is active with Full Calendar Access, seven synced
calendars and six selected-grid events. Accessibility remains unavailable;
the prior enabled-setting report does not prove approval for this exact binary.
Publication still requires exact-candidate canonical validation and hosted
checks, using the official matching 0.118.0 Debian image now published upstream.

scripts/check delegates to scripts/check.py, which runs ShellCheck, parses each zsh file, and executes the
standard-library unittest suite. .github/workflows/check.yml runs the same
suite on Linux and macOS with Python 3.14 and the required shell tools.
The tests exercise scoped installation, dry-run, backup and restore, refusal
to overwrite later edits, corruption detection, rollback after a simulated
failure, repeat runs, preservation of Git identity and Codex state, shell
re-sourcing, and worktree paths containing spaces.
Typed macOS preference tests cover absent keys, later edits, idempotence and
mid-application rollback. Container helper tests use a fake engine to verify
argument boundaries, project-only mounts and no automatic VM startup.

## Regression Guardrails

scripts/dotfiles doctor --all checks managed configuration, tool availability,
Ghostty validation, shell syntax, Git configuration, and Codex TOML.
It also verifies Chrome, native MLX and stored macOS preference values.
scripts/editor_check.py checks real language-server attachment for Python,
TypeScript, Lua, Bash, TOML and available Rust, Python project venv selection,
Ruff formatting and native TypeScript hover. Native file watchers on macOS
require execution outside a sandbox that denies filesystem event streams.
Font selection and interactive
shell widgets are checked on the Mac; MLX GPU imports require host Metal access.
VM image downloads and model inference are not part of portable unit tests.

## Evidence Artifacts

The host now uses Decapod 0.116.0, verified against the crates.io sparse index
and installed from the official GitHub release through cargo-binstall.
The owned verification image was refreshed from 0.115.0 to the same release.
The shared check owner ran in that image with its declared PATH: ShellCheck,
all zsh parsers and the earlier 30-test suite passed. This diagnostic execution is separate
from the required Decapod publication verdict.

The current local check suite passes 56 tests, including backup/restoration of
fractional Dock values and copied mise/reverse-shell settings. Installed doctor,
Ghostty validation, real editor LSP attachment, an isolated tmux server and the
Neovim workbench startup are separate host checks. MLX and Ollama inference and
Ghidra's ARM64/JDK diagnostics passed. A headless ARM64 engine and owned
verification container run successfully. Project prerequisites passed in that
container; full publication proof remains a separate required result. Ollama
was verified stopped with no process, listener or login plist; the foreground
helper's environment and arguments were verified with a stub without starting
the real server. Local configuration success does not establish
container-based Decapod publication readiness. Publication requires current task
authorization and passing exact-candidate validation.

The expanded suite protects desktop service ownership, guarded undo, native menu
recovery, stable LaunchAgent paths, cached hover response, stale-row cleanup,
safe device argv, clamped brightness/volume, Fahrenheit telemetry and MLX
activation/restore failure recovery. On macOS the shared check owner compiles
the native helper with warnings as errors, runs pure geometry tests across
1–40 apps and narrow displays, and typechecks wallpaper Swift. Linux runs the
portable suite; native compilation is separate macOS evidence.

Actual host apply reached fresh PID-bound health. The native brightness reader
works on the built-in display; the released Homebrew utility failed and was
removed. The dock's own view was rendered for inspection without screen
recording. MLX prepare verified the existing pinned Python 3.12/Metal stack
without loading a model. Native quick-panel Accessibility was denied during
the last local probe; installation does not prove those clicks or LuLu filtering
work. Mission Control integration is compiled but not a human gesture verdict.
Full publication validation must be rerun for this expanded candidate.

Palette tests require at least 4.5:1 declared contrast for text/control colors
against both theme surfaces, reject invalid selections and verify one-call
layout changes without item removal/reload. Actual host switching exercised
Ember/Islands, Iris/Ribbon and Tidal/Ribbon with the same healthy native PID.
Live SketchyBar color and bracket queries agree with Tidal; the three dock
palettes were inspected using the native view renderer. Full-screen capture
permission was unavailable, so this is narrower than a whole-screen visual audit.

Five weather regressions cover Fahrenheit/quantitative conversion, missing
values, stale labeling, offline retention/backoff, network-free hover with
14-row capacity and advertised API host checks. Actual ZIP97750 network fetch
returned24hourly periods, and the live item displayed49°F with its condition
glyph. This is forecast data, not an observation claim. The56-test source needs
fresh exact-candidate validation and hosted CI before merge; the earlier
51-test candidate passed both platforms and canonical local readiness.

## Promotion Gates

The native-panel elevation adds cached six-hour forecast tests covering imperial
conversion, expired periods, missing cache, invalid dates and precipitation,
without network access. Descriptor regressions cover finite bounded capacity,
missing memory totals and unchanged refresh-action indices. Native self-tests
reject malformed forecast arrays, unsupported conditions and meter values.
The native executable selector is tested with versioned-only Homebrew paths,
Intel fallback and no executable, protecting the observed missing-python3-link
failure without changing actual device settings in a test.
Dock tests compare smoothing after equal elapsed time at 30, 60 and 120 Hz,
require exact settlement, and retain the bottom-aligned geometry checks.
The ten account-free native preview fixtures expose typography, meter/graph
layout, forecast cards, action rows and sliders for visual inspection.
The host shared check owner compiles with warnings as errors and executes the
native self-tests; canonical exact-candidate readiness and hosted macOS/Linux
checks remain publication gates. Native helper changes require fresh live
health and separate verification of existing calendar permission after apply.
The applied elevation build reached fresh healthy PID-bound status with its
control backend available; ten panel routes and the one-second minute-only
clock were exercised on the host. The user approved the final build's standard
local calendar dialog, and fresh status reports Full Calendar Access, seven
synced calendars and six selected-grid events without retaining their titles.
Earlier-build consent alone was not used as evidence. App-menu Accessibility
remains separately pending and is not established by panel rendering tests.

The clock regression executes the actual status.sh clock route for routine,
desktop_revealed and system_woke events with only SketchyBar IPC replaced by a
recording function. Each emitted label must equal current system hours/minutes
and AM/PM without seconds. Live queries verify update_freq=1 and updates=on
independently of the compact display format. The earlier second-by-second live
comparison established hidden-bar advancement against the Mac's clock; cadence
and reveal/wake hooks remain unchanged by this presentation adjustment.
The native helper source and identity remain unchanged by this repair.

The Nocturne/native-panel refinement expands the shared suite to 67 tests.
It checks readable fourth-theme contrast, cached native descriptors, private
file modes, row replacement, canceled hover dwell, same-panel reuse, transfers,
stale device responses, stale native callbacks, slider bounds and failed-build
atomicity. macOS compilation uses warnings as errors with AppKit, QuartzCore,
EventKit and ApplicationServices. Native self-tests additionally cover 72 months,
leap years/DST/year navigation, malformed panel payloads and application-menu
index/current-app/disabled/submenu action guards. These tests require no real
calendar content or destructive menu actions.

Actual EventKit access is granted for the final native build and returns seven
synced calendars and selected-grid events, without recording titles. Accessibility
approval and actual menu interaction remain separate pending host evidence. Ad-hoc
native binary updates can require renewed consent. The generic
native control preview was inspected with deterministic fixture data. Exact
publication readiness and hosted Linux/macOS jobs remain required after source
and governance are finalized; compiled/tested does not establish OS consent.

The separate-pill refinement retains the shared 62-test check owner and native
checks. The live-layout regression now requires all three gap items to be
enabled with islands in the same IPC that disables the ribbon background.
Islands is the declared default; gap items are eight points wide and bracket
background padding is zero. Host apply and live queries verify the selection;
full exact-candidate readiness and Linux/macOS CI remain separate requirements.

The top-bar refinement passes 62 host tests, native warnings-as-errors
compilation, geometry checks and Swift typechecking. Six new hover regressions
cover canceled dwell, same-panel stability, atomic panel switching, the bridge
into information rows, stale row exits and late device responses. Telemetry
checks use utilization percentages at bar level while retaining Fahrenheit
in hardware hover details and preserving heat/swap warning colors.
Live queries verified three distinct drawn hardware icons, 44-point value
widths and opaque blur-free popups. The earlier temperature labels are
superseded by the user's utilization preference. Host desktop apply
reached fresh healthy state. These checks establish configured behavior;
whole-screen appearance and subjective pointer feel require user observation.
Fresh exact-candidate proof and hosted Linux/macOS jobs remain required.

The icons-only refinement supersedes the earlier dock chrome and palette
rendering. Host checks still pass 56 tests, native warnings-as-errors compilation,
geometry and Swift typechecking. An actual native DockView preview was inspected;
pixel alpha verification found zero nontransparent pixels in the upper/lower
background bands and 31,437 icon pixels. The panel has no shadow or visual-effect
view. These own-view checks do not require screen recording. Fresh exact-candidate
proof and hosted CI are required for this refinement before publication.

The subsequent reveal refinement passed the same 56 tests and native checks.
Pure geometry now asserts bottom-aligned icon rectangles, unchanged 40-point
resting size, a 77.5-point peak (62 times 1.25), and reveal coverage of future
resting icons on positive and negative display origins. Host apply reached
healthy service state with the bottom-aligned build. Pointer feel remains a
human interaction judgment; geometry and activation are verified separately.

Decapod's repo.pr-readiness.v1 profile executes the same portable check owner
through its Python entrypoint with an explicitly reviewed runtime closure inside
the configured container workspace. Proof is bound to the exact source candidate
and accepted target. Required commands, source coverage and runtime declarations
are review-pinned; init does not approve or execute them. Readiness failures remain
blocking. The profile attests repository-local execution, not GitHub-hosted Linux
and macOS jobs, release packaging or deployment. Those results remain separate.

Headless VM startup is mandatory. The observed debug-mode vfkit GUI behavior
is documented in DecapodLabs/decapod#1417. VM first-boot troubleshooting is
outside this change; do not claim container execution passed without evidence.

<!-- decapod:capability-overlay:persistent-state:start -->

Generated capability obligations: `persistent-state` is declared for this project. These are decisions and proof requirements, not claims of implemented behavior. Resolve each against project source and tests; record unsupported or non-applicable mechanisms explicitly.

## Persistent State Validation Overlay

### Migration Proof Command
- Configure `repo.migration_validation.command` and its arguments as the executable migration proof; file presence is not proof
- The configured command MUST define its working directory, timeout, expected exit code, and evidence output

### Migration Tests
- All migrations MUST have integration tests
- Rollback procedures MUST be tested
- Data integrity checks post-migration

### Persistence Integration Tests
- Repository abstraction tested against real database
- Transaction boundary tests
- Concurrency conflict tests
- Data integrity validation after recovery
<!-- decapod:capability-overlay:persistent-state:end -->

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `c90d7a78288a21050213593e790c937dd8687f29e3dc5391cf1bb2eba8f0d425`
- Significant implementation surfaces: `.config/` (4 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (10 files), `tests/` (6 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
