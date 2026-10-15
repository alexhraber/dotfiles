# Validation

## Proof Surfaces

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

The host now uses Decapod 0.115.0, verified against the crates.io sparse index
and installed from the official GitHub release through cargo-binstall.
The earlier owned verification image used 0.114.3 and must be refreshed.
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

- Repository signal fingerprint: `45d5943dc5bf0810673bea8f27bdbf72f5d029ac85a221ba183156d2ca1f97d6`
- Significant implementation surfaces: `.config/` (4 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (7 files), `tests/` (6 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
