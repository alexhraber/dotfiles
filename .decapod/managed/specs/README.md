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

- Repository signal fingerprint: `0229f36eed59a21f78229356fd3e926ab6826ee2829f8997aff2adce917fbf19`
- Significant implementation surfaces: `.config/` (3 files), `.github/` (1 files), `README.md/` (1 files), `scripts/` (7 files), `tests/` (5 files)
- Refreshed from the current codebase by `decapod rpc --op specs.refresh`
<!-- decapod:codebase-attestation:end -->
