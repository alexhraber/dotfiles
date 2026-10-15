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

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `565a71c979f06f17c41ba3d6b7655fe0f259bb145c4a7d039d23c4ea656feca1`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (4 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
