# Security and state boundaries

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

Subprocess arguments are passed as arrays. Shell helpers quote paths; tests
cover worktree destinations with spaces. Restore rejects later edits and corrupt
backups. The installer is local-user tooling, not a security boundary against a
malicious user-controlled backup manifest or repository.

Codex's workspace sandbox, network access preference and on-request approval
policy are retained. Local-model invocation does not disable these boundaries.
mlxserve binds to loopback by default. No network service is started at login.
All container workspaces must be headless, and access to the host's credentials
is never implied merely by creating a container.

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `6fba237828fbded719d7d827b3c1a53e8a4cf4a6874d4d4993811e935e34eac4`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (1 files), `tests/` (1 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
