# Semantics

## Invariants

Portable source files are the versioned source of truth. Most local configs
are symlinks; Codex files are copies because the application can update them.
An explicit Codex reinstall backs up local edits and reapplies tracked settings.

Installation is group-scoped, preflighted, backed up, and idempotent for matching
configuration. Directory destinations are rejected. Every changed file is
backed up before the first replacement. Each file replacement is atomic;
completed replacements are restored on a caught application failure.
An interrupted process can leave a partial multi-file installation; its manifest
and backups support recovery, rather than guaranteeing crash atomicity.

Restoration checks all destinations and backups before changing any target.
Later user edits and corrupted backups block restoration. Original symlinks are
restored as symlinks, so a separately updated repository still affects them.
Resolved-content backups preserve previous bytes for manual recovery.
Empty directories, installed packages and runtime caches are not rolled back.

Repeated sourcing of .zshrc does not duplicate hooks or reorder PATH. src starts
a fresh login shell. Missing modern tools leave standard commands usable. Local
model and VM commands are explicit; terminal startup launches no model server.

## State Machines

Installation proceeds from planned to preflighted to backed up to applied. A
caught failure restores completed operations. Preference application has its own
typed transaction and rollback. Restoration progresses only after every current
target and backup matches an accepted state; later edits reject the entire run.
Interruption leaves recovery artifacts rather than guaranteeing crash atomicity.

<!-- decapod:capability-overlay:persistent-state:start -->

Generated capability obligations: `persistent-state` is declared for this project. These are decisions and proof requirements, not claims of implemented behavior. Resolve each against project source and tests; record unsupported or non-applicable mechanisms explicitly.

## Persistent State Semantics Overlay

### Transaction Semantics
- Atomicity boundaries and any non-atomic operations MUST be declared with source and test evidence
- Document observed read-after-write behavior; do not infer consistency from a capability declaration
- Eventual consistency windows MUST be documented

### Migration Semantics
- Migration compatibility, any breaking changes, and their recovery path MUST be explicit and tested
- Migration rollback procedures MUST be documented
- Data integrity checks post-migration

### Recovery Semantics
- Document supported recovery mechanisms and evidence; point-in-time recovery is not implied by persistent-state
- Recovery objectives MUST be selected for the project and recorded as proof obligations
- Recovery test cadence MUST be selected for the project and recorded as a proof obligation
<!-- decapod:capability-overlay:persistent-state:end -->

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `91499f5aa1fd514d566d20a2035f6536e27bd313f811bfce537728e375048e47`
- Significant implementation surfaces: `.config/` (4 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (10 files), `tests/` (6 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
