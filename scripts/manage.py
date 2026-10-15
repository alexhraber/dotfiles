#!/usr/bin/env python3
"""Scoped dotfiles installation and conservative configuration restoration."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import macos_preferences

REPO = Path(__file__).resolve().parents[1]
GROUPS = ('terminal', 'git', 'codex', 'workspace', 'dev', 'reverse', 'apple', 'infra', 'ai', 'apps', 'macos')


def homes():
    home = Path.home()
    return home, Path(os.environ.get('XDG_CONFIG_HOME', home / '.config')), Path(os.environ.get('CODEX_HOME', home / '.codex'))


def state(path):
    if path.is_symlink():
        return {'type': 'symlink', 'value': os.readlink(path)}
    if path.is_file():
        return {'type': 'file', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'mode': path.stat().st_mode & 0o777}
    if path.exists():
        raise ValueError('Refusing to replace a directory or special file: ' + str(path))
    return {'type': 'absent'}


def select_groups(args):
    groups = list(GROUPS) if args.all else args.groups.split(',')
    if not groups or any(g not in GROUPS for g in groups):
        raise ValueError('Groups must be a comma-separated subset of ' + ','.join(GROUPS))
    return list(dict.fromkeys(groups))


def operation(target, source=None, content=None, remove=False, copy=False):
    item = {'target': str(target)}
    if remove:
        item['installed'] = {'type': 'absent'}
    elif source is not None and not copy:
        source = REPO / source
        if not source.is_file():
            raise ValueError('Missing source: ' + str(source))
        item['installed'] = {'type': 'symlink', 'value': str(source)}
    else:
        if source is not None:
            content = (REPO / source).read_bytes()
        if isinstance(content, str):
            content = content.encode()
        item['content'] = content
        item['installed'] = {'type': 'file', 'sha256': hashlib.sha256(content).hexdigest(), 'mode': 0o600}
    return item


def plan(groups, args):
    home, config, codex = homes()
    ops = []
    if 'terminal' in groups:
        for rel in ('.zprofile', '.zshrc'):
            ops.append(operation(home / rel, rel))
        ops.append(operation(home / '.tmux.conf', '.config/tmux/tmux.conf'))
        for rel in ('zsh/env.zsh', 'zsh/projects.zsh', 'zsh/local-models.zsh', 'ghostty/config', 'starship.toml', 'fastfetch/config.jsonc', 'bat/config', 'bat/themes/tokyonight_storm.tmTheme', 'lazygit/config.yml', 'nvim/init.lua', 'tmux/tmux.conf'):
            ops.append(operation(config / rel, '.config/' + rel))
        if sys.platform == 'darwin':
            ops.append(operation(home / 'Library/Application Support/com.mitchellh.ghostty/config.ghostty', '.config/ghostty/config'))
        legacy = [(config / 'herdr/config.toml', '.config/herdr/config.toml'),
                  (home / '.local/bin/dotfiles-startup', 'startup.sh')]
        for target, old_source in legacy:
            if target.is_symlink() and os.readlink(target) == str(REPO / old_source):
                ops.append(operation(target, remove=True))
    if 'git' in groups:
        ops.append(operation(config / 'git/dotfiles.gitconfig', '.gitconfig'))
        ops.append(operation(config / 'git/ignore', '.config/git/ignore'))
        target = home / '.gitconfig'
        include = str(config / 'git/dotfiles.gitconfig')
        with tempfile.TemporaryDirectory() as temp:
            draft = Path(temp) / 'gitconfig'
            draft.write_bytes(target.read_bytes() if target.exists() else b'')
            existing = subprocess.run(['git', 'config', '--file', str(draft), '--get-all', 'include.path'], capture_output=True, text=True)
            if existing.returncode not in (0, 1):
                raise ValueError('Existing Git configuration could not be parsed')
            if include not in existing.stdout.splitlines():
                subprocess.run(['git', 'config', '--file', str(draft), '--add', 'include.path', include], check=True)
                ops.append(operation(target, content=draft.read_bytes()))
        if args.git_name:
            local = home / '.gitconfig.local'
            public = Path(args.signing_key).expanduser()
            if not public.is_file() or public.suffix != '.pub':
                raise ValueError('--signing-key must name an existing SSH PUBLIC key (.pub)')
            key_fields = public.read_text().strip().split()
            if len(key_fields) < 2 or not key_fields[0].startswith('ssh-'):
                raise ValueError('Invalid SSH public key')
            with tempfile.TemporaryDirectory() as temp:
                draft = Path(temp) / 'local'
                draft.write_bytes(local.read_bytes() if local.exists() else b'')
                for key, value in [('user.name', args.git_name), ('user.email', args.git_email),
                                   ('gpg.format', 'ssh'), ('user.signingkey', str(public)),
                                   ('commit.gpgsign', 'true'), ('tag.gpgsign', 'true'),
                                   ('gpg.ssh.allowedSignersFile', str(config / 'git/allowed_signers'))]:
                    subprocess.run(['git', 'config', '--file', str(draft), key, value], check=True)
                ops.append(operation(local, content=draft.read_bytes()))
            signers = config / 'git/allowed_signers'
            old = signers.read_text() if signers.exists() else ''
            entry = args.git_email + ' ' + ' '.join(key_fields[:2])
            if entry not in old.splitlines():
                ops.append(operation(signers, content=old + ('\n' if old and not old.endswith('\n') else '') + entry + '\n'))
    if 'codex' in groups:
        for rel in ('config.toml', 'AGENTS.md', 'quick.config.toml', 'deep-review.config.toml'):
            # Copies keep app edits and account-specific settings out of Git.
            ops.append(operation(codex / rel, '.codex/' + rel, copy=True))
    if 'workspace' in groups:
        ops.append(operation(config / 'zsh/workspaces.zsh', '.config/zsh/workspaces.zsh'))
    if 'dev' in groups:
        # Copy so an applied worktree can be retained or merged independently.
        ops.append(operation(config / 'mise/config.toml', '.config/mise/config.toml', copy=True))
    if 'reverse' in groups:
        ops.append(operation(config / 'zsh/reverse.zsh', '.config/zsh/reverse.zsh', copy=True))
        local = home / '.zshrc.local'
        content = local.read_text() if local.exists() else ''
        source = '[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/reverse.zsh" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/reverse.zsh"'
        if source not in content.splitlines():
            ops.append(operation(local, content=content + ('\n' if content and not content.endswith('\n') else '') + source + '\n'))
    return ops


def apply(ops, dry_run=False):
    changes = []
    for item in ops:
        item['original'] = state(Path(item['target']))
        if item['original'] != item['installed']:
            changes.append(item)
    for item in changes:
        print(('Would update: ' if dry_run else 'Update: ') + item['target'])
    if dry_run or not changes:
        if not changes:
            print('Configuration already matches; no changes.')
        return None
    root = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'dotfiles/backups'
    root.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix=datetime.now().strftime('%Y%m%d-%H%M%S-'), dir=root))
    backup.chmod(0o700)
    for index, item in enumerate(changes):
        target = Path(item['target'])
        if item['original']['type'] != 'absent':
            saved = backup / str(index)
            shutil.copy2(target, saved, follow_symlinks=False)
            item['backup'] = str(saved)
            if target.is_symlink() and target.is_file():
                shutil.copy2(target, backup / (str(index) + '.resolved-content'))
    manifest = backup / 'manifest.json'
    public = [{k: v for k, v in item.items() if k != 'content'} for item in changes]
    manifest.write_text(json.dumps({'version': 1, 'repository': str(REPO), 'changes': public}, indent=2) + '\n')
    completed = []
    try:
        for item in changes:
            target = Path(item['target'])
            if state(target) != item['original']:
                raise ValueError('File changed during install: ' + str(target))
            install_item(item)
            completed.append(item)
    except Exception:
        for item in reversed(completed):
            restore_item(item)
        raise
    print('Backup manifest: ' + str(manifest))
    return manifest


def install_item(item):
    target = Path(item['target'])
    if item['installed']['type'] == 'absent':
        target.unlink(missing_ok=True)
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.dotfiles-', dir=target.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        if item['installed']['type'] == 'symlink':
            temporary.unlink()
            temporary.symlink_to(item['installed']['value'])
        else:
            temporary.write_bytes(item['content'])
            temporary.chmod(item['installed']['mode'])
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def restore_item(item):
    target = Path(item['target'])
    if item['original']['type'] == 'absent':
        target.unlink(missing_ok=True)
    else:
        original = item['original']
        replay = {'target': str(target), 'installed': original}
        if original['type'] == 'file':
            replay['content'] = Path(item['backup']).read_bytes()
        install_item(replay)


def restore(path, dry_run):
    manifest = Path(path).expanduser().resolve()
    document = json.loads(manifest.read_text())
    if document.get('kind') == 'macos-preferences':
        if sys.platform != 'darwin':
            raise ValueError('macOS preference restoration requires macOS')
        return macos_preferences.restore(document, dry_run)
    if document.get('version') != 1:
        raise ValueError('Unsupported backup manifest')
    changes = document['changes']
    for item in changes:
        current = state(Path(item['target']))
        if current not in (item['installed'], item['original']):
            raise ValueError('Restore would overwrite a later edit: ' + item['target'])
        if item['original']['type'] != 'absent':
            saved = Path(item['backup'])
            if saved.parent.resolve() != manifest.parent or state(saved) != item['original']:
                raise ValueError('Missing or changed backup: ' + str(saved))
    for item in reversed(changes):
        print(('Would restore: ' if dry_run else 'Restore: ') + item['target'])
        if not dry_run:
            restore_item(item)


def dependencies(groups, dry_run):
    command = ['brew', 'bundle', 'install', '--no-upgrade', '--file=' + str(REPO / 'Brewfile')]
    if dry_run:
        print('Would install Brewfile groups: ' + ','.join(groups))
    else:
        subprocess.run(command, env=dict(os.environ, HOMEBREW_DOTFILES_GROUPS=','.join(groups)), check=True)


def contains_preferences(actual, expected):
    """Allow app-owned metadata while detecting changes to portable preferences."""
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(key in actual and contains_preferences(actual[key], value) for key, value in expected.items())
    return actual == expected


def doctor(groups):
    failed = []
    def check(label, ok):
        print(('PASS ' if ok else 'FAIL ') + label)
        if not ok:
            failed.append(label)
    home, config, codex = homes()
    empty = argparse.Namespace(git_name=None, git_email=None, signing_key=None)
    for item in plan(groups, empty):
        if Path(item['target']) == codex / 'config.toml' and state(Path(item['target']))['type'] == 'file':
            continue  # Validate the portable keys below, retaining app metadata.
        check(item['target'], state(Path(item['target'])) == item['installed'])
    expected = {
        'terminal': ['ghostty', 'starship', 'fastfetch', 'fzf', 'zoxide', 'direnv', 'mise', 'eza', 'bat', 'rg', 'fd', 'lazygit', 'nvim', 'btop', 'tmux'],
        'git': ['git', 'delta'], 'codex': ['codex'], 'workspace': ['podman', 'decapod'],
        'dev': ['gh', 'jq', 'yq', 'uv', 'cargo-binstall', 'shellcheck', 'shfmt', 'actionlint', 'hadolint', 'ruff', 'basedpyright-langserver', 'tsc', 'typescript-language-server', 'bash-language-server', 'lua-language-server', 'taplo', 'cmake', 'ninja', 'pkg-config', 'ffmpeg'],
        'reverse': ['ghidraRun'],
        'apple': ['mas'] if sys.platform == 'darwin' else [],
        'infra': ['kubectl', 'helm', 'k9s', 'tofu', 'grpcurl'],
        'ai': ['ollama'], 'apps': [], 'macos': [],
    }
    for tool in dict.fromkeys(t for group in groups for t in expected[group]):
        check('command: ' + tool, shutil.which(tool) is not None)
    if 'terminal' in groups:
        if (home / '.cargo/env').is_file():
            result = subprocess.run(['zsh', '-ic', 'command -v cargo && command -v rustc'], env=dict(os.environ, TERM='dumb', FASTFETCH_DISABLE='1'), capture_output=True, text=True)
            check('Rust available in a fresh shell', result.returncode == 0)
        prefix = subprocess.check_output(['brew', '--prefix'], text=True).strip() if shutil.which('brew') else ''
        for plugin in ('zsh-autosuggestions', 'zsh-syntax-highlighting'):
            check(plugin, (Path(prefix) / 'share' / plugin / (plugin + '.zsh')).is_file())
        if shutil.which('ghostty'):
            result = subprocess.run(['ghostty', '+validate-config'], capture_output=True, text=True)
            check('Ghostty configuration', result.returncode == 0 and not result.stdout.strip() and not result.stderr.strip())
            if result.stdout or result.stderr:
                print(result.stdout + result.stderr)
        result = subprocess.run(['zsh', '-n', str(REPO / '.zshrc'), str(REPO / '.zprofile'), str(REPO / '.config/zsh/env.zsh'), str(REPO / '.config/zsh/projects.zsh')])
        check('zsh syntax', result.returncode == 0)
        result = subprocess.run(['zsh', '-n', str(REPO / '.config/zsh/local-models.zsh')])
        check('local model helper syntax', result.returncode == 0)
        if shutil.which('ollama'):
            print('INFO Ollama is available; models and service remain locally managed.')
        mlx = Path(os.environ.get('MLX_ENV', home / '.venvs/mlx')) / 'bin/mlx_lm.generate'
        if mlx.is_file():
            print('INFO MLX virtual environment is available: ' + str(mlx.parent.parent))
    if 'git' in groups:
        includes = subprocess.run(['git', 'config', '--global', '--get-all', 'include.path'], capture_output=True, text=True)
        check('Git includes portable settings', str(config / 'git/dotfiles.gitconfig') in includes.stdout.splitlines())
        check('Git author', subprocess.run(['git', 'var', 'GIT_AUTHOR_IDENT'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0)
    if 'codex' in groups:
        try:
            import tomllib
            for filename in ('config.toml', 'quick.config.toml', 'deep-review.config.toml'):
                try:
                    actual = tomllib.loads((codex / filename).read_text())
                    check('Codex TOML: ' + filename, True)
                    expected_config = tomllib.loads((REPO / '.codex' / filename).read_text())
                    check('Codex portable preferences: ' + filename, contains_preferences(actual, expected_config))
                except (ValueError, OSError):
                    check('Codex TOML: ' + filename, False)
        except ImportError:
            check('Python 3.11+ for TOML validation (install Brewfile dependencies)', False)
    if 'apps' in groups and sys.platform == 'darwin':
        check('Google Chrome application', Path('/Applications/Google Chrome.app').is_dir())
    if 'ai' in groups and sys.platform == 'darwin' and os.uname().machine == 'arm64':
        # Native MLX has no CLI; Python MLX-LM remains in its separate venv.
        result = subprocess.run(['brew', 'list', '--versions', 'mlx'], capture_output=True, text=True)
        check('Native MLX formula', result.returncode == 0 and bool(result.stdout.strip()))
    if 'macos' in groups and sys.platform == 'darwin':
        pending = macos_preferences.plan(REPO / '.config/macos/preferences.json')
        check('macOS developer preferences', not pending)
        for item in pending:
            print('INFO preference differs: ' + item['domain'] + '/' + item['key'])
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('install', 'doctor', 'restore'))
    parser.add_argument('manifest', nargs='?')
    parser.add_argument('--groups', default='terminal')
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--deps', action='store_true', help='Install selected Brewfile dependencies without upgrading')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--restore', dest='restore_manifest', help='Restore a backup manifest (also accepted by install.sh)')
    parser.add_argument('--git-name')
    parser.add_argument('--git-email')
    parser.add_argument('--signing-key', help='Public SSH key used for Git signing; identity stays local')
    args = parser.parse_args()
    if args.restore_manifest or args.command == 'restore':
        manifest = args.restore_manifest or args.manifest
        if not manifest:
            parser.error('restore requires a manifest')
        restore(manifest, args.dry_run)
        return 0
    if args.manifest:
        parser.error('a manifest is only accepted by restore')
    groups = select_groups(args)
    identity = (args.git_name, args.git_email, args.signing_key)
    if any(identity) and (not all(identity) or 'git' not in groups):
        parser.error('Git signing requires the git group, --git-name, --git-email, and --signing-key')
    if args.command == 'doctor':
        return doctor(groups)
    ops = plan(groups, args)
    preferences = macos_preferences.plan(REPO / '.config/macos/preferences.json') if 'macos' in groups and sys.platform == 'darwin' else []
    for item in ops:
        state(Path(item['target']))
    if args.deps:
        dependencies(groups, args.dry_run)
    apply(ops, args.dry_run)
    if 'macos' in groups:
        if sys.platform == 'darwin':
            macos_preferences.apply(preferences, args.dry_run)
        else:
            print('INFO macOS preference group skipped on this platform.')
    if 'terminal' in groups and not args.dry_run and shutil.which('bat'):
        subprocess.run(['bat', 'cache', '--build'], check=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('dotfiles: ' + str(error), file=sys.stderr)
        sys.exit(1)
