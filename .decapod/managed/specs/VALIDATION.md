# Validation

## Repository checks

scripts/check runs ShellCheck, parses each zsh file, and executes the
standard-library unittest suite. .github/workflows/check.yml runs the same
suite on Linux and macOS with Python 3.14 and the required shell tools.
The tests exercise scoped installation, dry-run, backup and restore, refusal
to overwrite later edits, corruption detection, rollback after a simulated
failure, repeat runs, preservation of Git identity and Codex state, shell
re-sourcing, and worktree paths containing spaces.
Typed macOS preference tests cover absent keys, later edits, idempotence and
mid-application rollback. Container helper tests use a fake engine to verify
argument boundaries, project-only mounts and no automatic VM startup.

## Local checks

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

## Decapod limitation

Decapod 0.111.1 initialization and workspace bookkeeping work, but its complete
readiness profile is compiled for Decapod's own Rust repository and specific
workflow/helper definitions. This dotfiles repository has a different contract.
The external proof runner also denies the custom check helper under its default
proof_exec policy. Running scripts/check directly supplies repository evidence; it does not constitute
full Decapod publication readiness. No placeholder adapter or green receipt is
invented. Kernel readiness failures remain explicit and are separate from the
actual dotfiles tests and the user's authorized direct main publication.

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

- Repository signal fingerprint: `bd87ea8ea1effbcd9214006f360947918b918f94b45b80ee867599d5e1d77e51`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (3 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
