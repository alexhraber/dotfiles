# alexhraber/dotfiles

A reproducible engineering workstation: Ghostty, Tokyo Night Storm,
JetBrainsMono Nerd Font, Starship, zsh, tmux, polyglot Neovim, Git, Codex,
local AI, infrastructure tools, and reversible macOS preferences. Podman is
the intended container runtime; Decapod is initialized for isolated workspaces.

The target workstation is an Apple M1 Max MacBook Pro. All authored configuration
and automation live in `~/src/dotfiles`; installed shell/editor configuration
links to the main checkout. Mutable Codex preferences are copied deliberately.
Homebrew installs native Apple-silicon tools. Credentials, model stores, VM disks,
application state and private backup manifests stay outside Git.

Treat changes as infrastructure as code: edit a declared dependency or config,
inspect `./install.sh --all --deps --dry-run`, run `scripts/check`, apply,
then run `scripts/dotfiles doctor --all` and the
relevant integration check. Repeated apply converges to the declared state;
doctor detects configuration drift. Only `macos` changes user defaults, with
per-key backups. Package versions are moving releases, so reproducibility here
means declared tools and preferences, not byte-identical system images.

## Install

Homebrew and Python 3 are needed to bootstrap. The dependency installer adds
Python 3.14 for configuration validation. Inspect `Brewfile` and `install.sh`
before applying a new checkout.

```sh
./install.sh --dry-run --deps       # Preview the default terminal group
./install.sh --deps                 # Install tools and terminal/editor config
./install.sh --all --deps           # Full workstation, including macOS preferences
exec zsh -l
```

Select any combination with `--groups terminal,git`. The default stays
`terminal`; `--all` explicitly selects every group:

| Group | Managed setup |
| --- | --- |
| terminal | Ghostty, shell, tmux, editor, navigation and terminal tools |
| git | Portable Git settings, delta, global OS/editor ignore file |
| codex | Codex app, portable CLI preferences and instructions |
| workspace | Podman and the explicit `cws` container helper |
| dev | GitHub CLI, jq/yq, uv, Cargo binary installer, linters, language servers, CMake/Ninja/pkg-config and FFmpeg |
| reverse | Ghidra and its Homebrew-managed JDK for REA native analysis |
| apple | Mac App Store CLI for the explicit, interactive Xcode setup script |
| infra | kubectl, Helm, k9s, OpenTofu and grpcurl |
| ai | Ollama and native MLX on Apple silicon |
| apps | Google Chrome |
| macos | Finder, keyboard, text input, Dock and screenshot preferences |

Dependency installation uses a curated Brewfile
and `--no-upgrade`; it does not remove unrelated packages. Podman is installed
by the workspace group. Rust and Decapod remain managed by your existing rustup
and Cargo installation. The Brewfile tracks direct tools, not their transitive
libraries. An existing manually installed Chrome is retained; a missing Chrome
is installed through its cask. Existing Homebrew-managed Chrome remains in the
bundle. This avoids administrator-password requirements during app adoption;
the installer never uses `--force` or deletes browser profiles. Node and TypeScript are
Homebrew dependencies of language servers. Application runtime versions belong
in projects using mise, uv or rustup.

The dev group copies `.config/mise/config.toml` with the same backup/restore
rules as other configuration. It selects Node 24.18.0 and npm 11.16.0, matching
REA's development pins, and enables project `.nvmrc`/`.node-version` and
`packageManager` selection. Existing mise activation in zsh switches versions
when entering projects. Install the declared runtimes explicitly with
`mise install`; a shell does not install them. See [mise's Node documentation](https://mise.jdx.dev/lang/node.html).
Rust remains under rustup: the current Decapod checkout needs
`rustup toolchain install 1.96.1 --profile minimal --component rustfmt,clippy,rust-analyzer`.

For REA's Ghidra backend, install `--groups reverse --deps`. A copied shell
helper discovers Homebrew Ghidra and JDK 21 through `HOMEBREW_PREFIX`, preserving
explicit `GHIDRA_INSTALL_DIR` and `JAVA_HOME` choices. Its source line is added
to `.zshrc.local` with backup/restore and without replacing other local settings.
The engine is headless unless explicitly launched; the
installer does not register an MCP server or change agent authentication.

Full Xcode and its iOS SDK are required for Scripture's simulator/device builds.
Run `scripts/setup-xcode` in a visible terminal after installing the apple group.
It installs Apple's Xcode through `mas`, selects the toolchain, presents the
license for local review, runs first-launch setup and downloads the iOS platform.
Mac administrator and App Store authentication happen locally. Then sign in to
Xcode Settings > Accounts for Personal Team development signing. Certificates,
provisioning profiles, Team IDs and signing keys remain outside Git. Command
Line Tools alone provide Swift and macOS compilation, without iOS builds.

Apple development team selection is deliberately not saved here. A future agent
must ask which team to use when signing is needed, then populate only local
project settings or command-line overrides. Do not commit team names, Team IDs,
Xcode account preferences, private signing projects or provisioning assets.

Use the scripts directly; no task runner is required. Preview with
`./install.sh --all --deps --dry-run`, apply with `./install.sh --all --deps`,
check with `scripts/check`, and inspect the installation with
`scripts/dotfiles doctor --all`. `brew bundle check --no-upgrade --file=Brewfile`
checks declared packages; `brew outdated` reports updates without applying them.
Homebrew packages are current releases, not version-pinned; Neovim plugins
are pinned separately.

The installer validates destinations before changing files, saves every
conflicting file or symlink in a private backup directory, and writes a JSON
manifest. Repeated installs make no configuration changes when files already
match. Ghostty's XDG and macOS application-support config locations are both
managed so they cannot accidentally disagree. No LaunchAgents or background
application services are installed.

Backups default to `~/.local/state/dotfiles/backups/`; the exact manifest path
is printed after installation. Restore configuration with:

```sh
./install.sh --restore /path/to/manifest.json --dry-run
./install.sh --restore /path/to/manifest.json
```

Restore checks all targets and backups first and refuses to overwrite later
edits. It restores original symlinks as symlinks; `.resolved-content` files also
preserve their original contents. Restoration does not undo repository updates,
package installations, plugin downloads, or runtime caches. Existing directories
are never replaced. `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, and `CODEX_HOME` are
respected when set.

## macOS preferences

`.config/macos/preferences.json` shows file extensions, Finder path/status bars
and searches the current folder; enables fast key repeat; disables smart quotes,
dashes, automatic periods and spelling correction; hides recent apps in the Dock;
and stores PNG screenshots in `~/Pictures/Screenshots`.

The macOS group also uses Finder list view and a compact, auto-hiding Dock with
windows minimized into their application icons. It backs up only changed keys,
preserving boolean, integer, floating-point and string types and absent keys,
then applies and reads each key back. A failed application rolls back preference
changes. Its separate private manifest uses the same `--restore` command and
refuses to overwrite later edits. File installation and preferences are separate
transactions. The screenshot directory and contents remain during restore.
On Linux, the macOS group is skipped.

Existing apps may need reopening or logout before consuming the preferences;
the installer does not restart Finder or Dock. Apple documents
[Finder settings](https://support.apple.com/guide/mac-help/change-finder-settings-on-mac-mchlp2803/mac)
and [key repeat](https://support.apple.com/en-gb/guide/mac-help/mchl0311bdb4/mac).
CLI keys are verified on the installed macOS version, not treated as a stable
cross-version API. Security controls, cloud accounts, keychains, accessibility
permissions and browser profiles remain locally managed.

## Shell and projects

Login and non-login interactive zsh share `.config/zsh/env.zsh`. It detects the
Homebrew prefix, adds local tools, and sources `~/.cargo/env` when available.
Mise can put its project shims ahead of these paths. Plugins are registered once
per shell; `src` starts a fresh login shell to reload changes. Optional local
settings go in `~/.zshrc.local` and remain outside Git.

- `proj`: fuzzy-pick a directory under `~/src` (override with `PROJECTS_DIR`).
- `wt`: fuzzy-pick a Git worktree of the current repository.
- `wtnew <new-branch> <directory>`: create a worktree and enter it.
- `v`, `vi`: Neovim when installed, with a system-editor fallback.
- `lg`: Lazygit; `gs`, `gd`, `gds`, `gl`: common Git views.
- `dotfiles doctor --all`: inspect the installed configuration and dependencies.
- `tm`: create or attach the `main` tmux session; Ctrl-b remains the prefix.
- `cws <image> [command ...]`: run in the current project through Podman.

Modern command aliases are enabled only when their tools exist. `grep` keeps its
standard behavior; invoke `rg` directly. Fastfetch runs in interactive login
terminals; set `FASTFETCH_DISABLE=1` to skip it. Ghostty retains its standard
split, tab, zoom, and reload shortcuts.

The rice uses a steady block cursor, subtle Ghostty translucency, matching fzf
colors, file previews on Ctrl-T and directory previews on Alt-C. Ctrl-/ toggles
the preview. Starship hides local account/hostname noise, keeps SSH identity,
and shows project runtimes, bounded Git branch names, command duration and time.
Tmux uses a top status bar and pane labels: Ctrl-b then h/j/k/l selects a pane,
Shift-h/j/k/l resizes it, Tab returns to the previous window, and | / - split.

## Neovim

The configuration requires Neovim 0.12+. Native `vim.pack` installs two plugins
from HTTPS on first startup: Tokyo Night and mini.nvim. Both are pinned to
specific commits in `.config/nvim/init.lua`. No additional language runtimes
are installed when opening files. Plugin checkouts and the generated package
lockfile stay in Neovim's local directories.

Use Space as the leader:

| Keys | Action |
| --- | --- |
| Space ff / fg / fb / fh | Find files, live text search, buffers, help |
| Space e | File explorer |
| Space gs | Pick Git hunks |
| Space w / q | Save / open quickfix |
| Ctrl h / j / k / l | Move between splits |
| gd / gr / K | Definition, references, hover with an attached language server |
| Space rn / ca / cf | Rename, code action, format with an attached server |

Persistent undo, completion, surrounding pairs, Git diff signs, and a statusline
are enabled. The dev group supplies Basedpyright/Ruff for Python, TypeScript
7's native LSP for JS/TS/React, Bash language server, Lua language server and
Taplo for TOML. Python prefers the project's `.venv`; Ruff owns formatting and
import actions while Basedpyright supplies types and navigation. Space cd shows
line diagnostics; Space cq sends diagnostics to quickfix. Servers are enabled
only when their binaries are available. Projects with a local pre-7 TypeScript
installation use the legacy language-server wrapper and their own tsserver.
Deno projects are left to local configuration. Neovim supports project EditorConfig.

Rust LSP uses `rust-analyzer` from the existing Rust toolchain;
install that component with `rustup component add rust-analyzer`. Optional
language-server configuration and local settings belong in
`~/.config/nvim/local.lua` (or the equivalent XDG path).

Neovim opens a centered workbench with file search, project search and recent
files. Space ss reopens it; [b / ]b switches buffers. A tabline, static indent
guides and rounded floating windows use the same pinned mini.nvim package.

Tokyo Night Storm is shared by Ghostty, Neovim, Starship, bat, delta, and Lazygit.
The installer builds bat's theme cache. Its vendored theme is attributed and
licensed in `.config/bat/themes/NOTICE` and `LICENSE`.

## Git and signing

The Git group adds an include to your existing `~/.gitconfig`, preserving
identity, credential helpers, and other settings. Portable behavior lives in
`.gitconfig`; machine-specific overrides live in `~/.gitconfig.local`.

Pulls require a fast-forward; new branch pushes set their upstream; rerere
remembers conflict resolutions without automatically staging them. The global
ignore uses Git's native XDG location and covers OS/editor debris; project build
artifacts belong in project ignores. Existing custom `core.excludesFile` overrides
remain local. GitHub CLI authentication requires an explicit `gh auth login` and
stays outside the repository; SSH Git authentication and signing are independent.

Configure an identity and SSH signing explicitly, using a **public** key:

```sh
./install.sh --groups git \
  --git-name 'Your Name' \
  --git-email 'your-email@example.com' \
  --signing-key "$HOME/.ssh/id_ed25519_github.pub"
```

The local signing configuration and allowed-signers file are backed up before
changes. Key material is never copied into this repository. The matching private
key must be available locally or through an SSH agent, and GitHub needs the
public key registered for signing as well as authentication.

## Codex

Only portable preferences, concise global instructions, and CLI profile files
are tracked. Installation copies them to Codex home with mode 0600, so app edits
cannot write credentials or machine settings back into the repository. A later
explicit Codex reinstall backs up local changes and reapplies the tracked files.
Authentication, sessions, databases, caches, downloaded plugins, and accumulated
approval rules remain local.

```sh
codex                         # Existing model preference, high effort
codex --profile quick         # Medium effort
codex --profile deep-review   # Extra-high effort
```

Profile files use top-level keys, following the current
[Codex profile format](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles).
Global `AGENTS.md` contains working preferences; repository instructions remain
specific to each project. Approval and sandbox boundaries are preserved.

## Existing local models

Ollama stays off until explicitly started. Run `aiup` in a terminal, use
Ollama clients in another terminal, then press Ctrl-C in the server terminal
when finished. The helper runs `ollama serve` in the foreground, preloads no
model, and defaults to unloading models after each response with
`OLLAMA_KEEP_ALIVE=0`. It also enables Flash Attention and the `q8_0` KV cache.
Clients can override the unload default with an explicit `keep_alive` request.
See the [Ollama memory settings](https://docs.ollama.com/faq#how-do-i-keep-a-model-loaded-in-memory-or-make-it-unload-immediately).

For an existing Homebrew service, `brew services stop ollama` stops it and
unregisters login startup. Avoid `brew services start ollama` for this manual
workflow, since it registers login startup. The installer never enables it.

`cxlocal` starts Codex explicitly with Ollama and the already-installed
`qwen3-coder:30b` model. Set `CODEX_LOCAL_MODEL` to choose another local model.
It preserves approval and sandbox settings; ordinary `codex` keeps the cloud
model preference. Ollama's service and model files remain locally managed.

`mlx`, `mlxchat`, and `mlxserve` use the existing `~/.venvs/mlx` environment
without changing the shell's Python. Override its location with `MLX_ENV`.
`mlxserve` binds to loopback unless explicitly overridden. These commands do
not run during shell startup or automatically download models.

The Brewfile includes native MLX. Python MLX-LM uses the pinned Apple-silicon
Python 3.12 requirements in `requirements/mlx.txt`. Prepare an environment at
its permanent path before switching the stable `~/.venvs/mlx` link:

```sh
uv venv --python 3.12 ~/.venvs/mlx-0.32.0-py312
uv pip sync --python ~/.venvs/mlx-0.32.0-py312/bin/python requirements/mlx.txt
```

Verify Metal and a cached model before switching. Preserve an existing
`~/.venvs/mlx` directory or symlink in a private backup, then link that name to
the prepared environment. Virtual environments must not be moved after creation
because their entrypoints contain absolute paths. The regular installer never
replaces environments, changes GPU memory limits or downloads models. Model
stores and environment backups remain local state. Regenerate the lock on an
Apple-silicon Mac with `uv pip compile requirements/mlx.in --python 3.12 --output-file requirements/mlx.txt --no-header`.

## Podman and Decapod

On macOS, Podman runs containers inside a Linux VM. The installer installs the
CLI; VM creation and startup are explicit operations:

```sh
podman machine list
podman machine init --cpus=4 --memory=4096 --disk-size=100 dotfiles
podman machine start --quiet --no-info dotfiles
podman info
```

Use an existing machine when one is already configured. VM disks, SSH keys,
connections, sessions, and container state remain local. No login service is
installed. Start the VM before using container workspaces. All VM starts must be headless;
do not enable Podman debug logging on macOS, since it adds the vfkit GUI.

`cws` checks an already-running engine and never starts a machine. Supply a
fully qualified image, preferably pinned by digest, and an optional command.
It shares only the current project at `/workspace`, uses `keep-id`, drops Linux
capabilities, blocks privilege escalation, and allocates a TTY only interactively.
Source is writable from the container. SELinux labeling is disabled for this
invocation to support shared macOS filesystems. Host auth directories, SSH agents, engine
sockets and home directories are not mounted. It refuses to mount home or `/`.
It is a development helper, not a security boundary for untrusted project code.

This repository is initialized with Decapod's local backend and container
isolation. Follow `AGENTS.md` and `decapod docs ingest` for its session, task,
workspace, and validation lifecycle. Podman is the intended local runtime.
The authored specifications under `.decapod/managed/specs/` describe this
repository; runtime state is ignored. Decapod initialization by itself does not
prove that repository checks or publication readiness passed. The supported
`repo.pr-readiness.v1` profile runs the same portable checks through
`scripts/check.py` in the verification image, using reviewed source/command
digests and an explicitly declared tool directory. The Bash entrypoint and CI
delegate to that same check owner. This proves repository-local execution;
GitHub's Linux/macOS jobs and host editor/model checks remain separate evidence.
All VM startup must remain headless; see [the upstream startup issue](https://github.com/DecapodLabs/decapod/issues/1417).

## Verification

```sh
scripts/check                  # ShellCheck, zsh syntax, and isolated tests
scripts/dotfiles doctor --all   # Dependencies and installed configuration
python3.14 scripts/editor_check.py  # Real installed language servers and formatting
```

The tests exercise scoped installation, backups, rollback on failure, repeated
installation, restoration, refusal to overwrite later edits, preservation of Git
identity and Codex state, worktree paths with spaces, shell hook behavior,
typed preference backup/restore and failure rollback, and container arguments
with a fake engine that proves no automatic VM startup occurs.
GitHub Actions runs the same suite on Linux and macOS. Config and package checks
on the actual Mac are separate from the portable test suite.
