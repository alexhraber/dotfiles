# Project specifications

These documents describe alexhraber/dotfiles, a personal macOS terminal,
editor, Git, and Codex setup. The user-facing interface is documented in the
root README.md; the implementation lives in scripts/manage.py and the tracked
configuration files.

INTENT.md covers outcomes and scope; ARCHITECTURE.md maps components;
INTERFACES.md defines commands and backup manifests; SEMANTICS.md records
installation and restoration rules; OPERATIONS.md covers local use;
SECURITY.md identifies credential and machine-state boundaries;
VALIDATION.md distinguishes test evidence from Decapod readiness.

The repository has no HTTP service, queue, hosted application, or release
package. The removed AMP/Tailscale LaunchAgent and Herdr configuration are
outside the intended setup. Generated Decapod overlays express obligations;
they are not evidence of runtime guarantees.

<!-- decapod:codebase-attestation:start -->

## Codebase Attestation

- Repository signal fingerprint: `9a7da8d053d167c923de250f90f469856dcbb11aa390179091a488611dc58b74`
- Significant implementation surfaces: `.github/` (1 files), `README.md/` (1 files), `scripts/` (4 files), `tests/` (3 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
