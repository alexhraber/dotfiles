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

- Repository signal fingerprint: `c651940cee68383c9f25d55e5530df3d639c5b9eeeffbcda48ab3da369c9c502`
- Significant implementation surfaces: `.config/` (6 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (14 files), `tests/` (9 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
