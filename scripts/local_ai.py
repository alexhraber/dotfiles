"""Prepare and verify pinned MLX environments without starting any model."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
REQUIREMENTS = ROOT / 'requirements/mlx.txt'


def pointer_state(path):
    if path.is_symlink():
        return {'type': 'symlink', 'value': os.readlink(path)}
    if path.is_dir():
        return {'type': 'directory'}
    if path.exists():
        raise ValueError('MLX path must be a virtual environment directory or symlink')
    return {'type': 'absent'}


def save(path, document):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(document, indent=2) + '\n')
    temporary.chmod(0o600)
    os.replace(temporary, path)


def link(path, target):
    temporary = path.with_name('.mlx-link-' + uuid.uuid4().hex)
    temporary.symlink_to(target)
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def activate(stable, target, manifest):
    document = json.loads(manifest.read_text()) if manifest.exists() else None
    first = not document or not document['active']
    if first:
        original = pointer_state(stable)
        document = {'version': 1, 'active': True, 'original': original,
                    'installed': str(target), 'stable': str(stable)}
        if original['type']=='directory':
            document['backup'] = str(stable.with_name('.mlx-before-' + uuid.uuid4().hex))
        save(manifest, document)
        if original['type']=='directory':
            try:
                os.replace(stable, document['backup'])
            except Exception:
                document['active'] = False
                save(manifest,document)
                raise
    elif pointer_state(stable) != {'type': 'symlink', 'value': document['installed']}:
        raise ValueError('MLX stable path changed after preparation; refusing to replace it')
    try:
        link(stable, target)
    except Exception:
        if first and document['original']['type']=='directory' and pointer_state(stable)['type']=='absent':
            os.replace(document['backup'], stable)
        if first:
            document['active'] = False
            save(manifest,document)
        raise
    document['installed'] = str(target)
    save(manifest, document)


def restore(manifest):
    document = json.loads(manifest.read_text())
    if not document['active']:
        return
    stable = Path(document['stable'])
    if pointer_state(stable) != {'type':'symlink','value':document['installed']}:
        raise ValueError('MLX stable path was edited later; refusing to overwrite it')
    original = document['original']
    if original['type']=='symlink':
        link(stable, original['value'])
    elif original['type']=='directory':
        backup = Path(document['backup'])
        if not backup.is_dir():
            raise ValueError('Original MLX directory backup is missing')
        stable.unlink()
        try:
            os.replace(backup, stable)
        except Exception:
            link(stable, document['installed'])
            raise
    else:
        stable.unlink()
    document['active'] = False
    save(manifest, document)


def expected_packages():
    result = {}
    for line in REQUIREMENTS.read_text().splitlines():
        match = re.fullmatch(r'([A-Za-z0-9_.-]+)==([^\s;]+)', line.strip())
        if match:
            result[re.sub(r'[-_.]+','-',match[1]).lower()] = match[2]
    return result


def packages_match(environment):
    python = environment / 'bin/python'
    if not python.is_file():
        return False
    result = subprocess.run(['uv','pip','list','--python',str(python),'--format','json'],
                            capture_output=True,text=True,check=True)
    actual = {re.sub(r'[-_.]+','-',item['name']).lower():item['version'] for item in json.loads(result.stdout)}
    return all(actual.get(name)==version for name,version in expected_packages().items())


def verify(environment):
    python = environment / 'bin/python'
    subprocess.run(['uv','pip','check','--python',str(python)],check=True)
    subprocess.run([str(python),'-c',
        'import sys; import mlx.core as mx; import mlx_lm; '
        'assert sys.version_info[:2] == (3,12), "MLX requires the declared Python 3.12"; '
        'assert mx.metal.is_available(), "Metal unavailable"; '
        'print("MLX and MLX-LM verified on native Metal. No model loaded.")'],check=True)


def main(action, dry_run=False):
    if platform.system()!='Darwin' or platform.machine()!='arm64':
        raise ValueError('Pinned MLX preparation requires an Apple Silicon Mac')
    if os.environ.get('MLX_ENV'):
        raise ValueError('Unset MLX_ENV to manage ~/.venvs/mlx; the explicit external environment is preserved')
    stable = Path.home()/'.venvs/mlx'
    state = Path(os.environ.get('XDG_STATE_HOME',Path.home()/'.local/state'))/'dotfiles/mlx'
    manifest = state/'manifest.json'
    if dry_run:
        print('Would prepare requirements/mlx.txt under ~/.venvs, verify Metal, then switch ~/.venvs/mlx with a private recovery manifest.')
        return 0
    state.mkdir(parents=True,exist_ok=True,mode=0o700)
    state.chmod(0o700)
    with (state/'prepare.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if action=='undo':
            if manifest.exists():
                restore(manifest)
            print('Original MLX environment restored; prepared environments and model cache retained.')
            return 0
        if packages_match(stable):
            verify(stable)
            print('The existing MLX environment matches the declared pins; no replacement needed.')
            return 0
        if action=='status':
            print('MLX environment differs from requirements/mlx.txt. Use: scripts/dotfiles ai prepare')
            return 1
        digest = hashlib.sha256(REQUIREMENTS.read_bytes()).hexdigest()[:12]
        target = stable.parent/('mlx-'+digest+'-py312')
        marker = target/'.dotfiles-managed'
        if target.exists() and (not marker.is_file() or marker.read_text()!=digest):
            raise ValueError('Unowned MLX preparation directory exists; refusing to modify '+str(target))
        target.mkdir(parents=True,exist_ok=True,mode=0o700)
        marker.write_text(digest)
        marker.chmod(0o600)
        subprocess.run(['uv','venv','--allow-existing','--python','3.12',str(target)],check=True)
        subprocess.run(['uv','pip','sync','--python',str(target/'bin/python'),str(REQUIREMENTS)],check=True)
        verify(target)
        activate(stable,target,manifest)
        print('MLX prepared. Undo: scripts/dotfiles ai undo')
        print('Private recovery manifest: '+str(manifest))
        return 0
