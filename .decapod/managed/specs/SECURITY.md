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

Desktop activation is explicit. The helper uses private SkyLight menu calls,
DisplayServices brightness and a Mission Control notification with SIP enabled;
it does not inject code, install an event tap, warp the pointer or require root.
An OS update may change these interfaces. Ordinary failure restores the native
menu; SIGKILL cannot run cleanup, and the owned LaunchAgent restarts the helper.
Undo recovers the menu before checking guarded preference restoration.

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

- Repository signal fingerprint: `c55e37c9730ea2f3cd8d6824221a63811dead18e1216de1c705a501150254036`
- Significant implementation surfaces: `.config/` (4 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (7 files), `tests/` (6 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
