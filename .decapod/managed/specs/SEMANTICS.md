# Semantics

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

- Repository signal fingerprint: `0ff7c179bd7a6bce3e6996877b6119c569389b8ffce232a77eedb6565ca32d8d`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (3 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
