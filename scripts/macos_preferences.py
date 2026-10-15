"""Per-key macOS preferences, with typed backups and guarded restoration."""
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

TYPES = {bool: 'bool', int: 'int', float: 'float', str: 'string'}


def typed(value):
    if type(value) not in TYPES:
        raise ValueError('Unsupported preference type; refusing to replace it')
    return {'type': TYPES[type(value)], 'value': value}


def read_domain(domain):
    result = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True, check=True)
    return plistlib.loads(result.stdout)


def current(item):
    values = read_domain(item['domain'])
    return typed(values[item['key']]) if item['key'] in values else None


def plan(source):
    desired = json.loads(Path(source).read_text())
    changes = []
    for domain, settings in desired.items():
        existing = read_domain(domain)
        for key, value in settings.items():
            if isinstance(value, str) and value.startswith('~/'):
                value = str(Path(value).expanduser())
            item = {'domain': domain, 'key': key, 'installed': typed(value),
                    'original': typed(existing[key]) if key in existing else None}
            if item['original'] != item['installed']:
                changes.append(item)
    return changes


def write(item, value):
    prefix = ['defaults']
    if value is None:
        if current(item) is not None:
            subprocess.run(prefix + ['delete', item['domain'], item['key']], check=True)
    else:
        raw = value['value']
        # JSON booleans need defaults' explicit boolean spelling.
        argument = ('true' if raw else 'false') if value['type'] == 'bool' else str(raw)
        subprocess.run(prefix + ['write', item['domain'], item['key'], '-' + value['type'], argument], check=True)
    if current(item) != value:
        raise ValueError('Preference did not persist: ' + item['domain'] + '/' + item['key'])


def apply(changes, dry_run=False):
    for item in changes:
        print(('Would set preference: ' if dry_run else 'Set preference: ') + item['domain'] + '/' + item['key'] + ' = ' + str(item['installed']['value']))
    if dry_run or not changes:
        if not changes:
            print('macOS preferences already match; no changes.')
        return None
    root = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'dotfiles/backups'
    root.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix=datetime.now().strftime('%Y%m%d-%H%M%S-macos-'), dir=root))
    backup.chmod(0o700)
    manifest = backup / 'manifest.json'
    manifest.write_text(json.dumps({'version': 1, 'kind': 'macos-preferences', 'changes': changes}, indent=2) + '\n')
    manifest.chmod(0o600)
    completed = []
    try:
        for item in changes:
            if current(item) != item['original']:
                raise ValueError('Preference changed during install: ' + item['key'])
            if item['domain'] == 'com.apple.screencapture' and item['key'] == 'location':
                Path(item['installed']['value']).mkdir(parents=True, exist_ok=True)
            # Include this key in rollback even if write/readback fails.
            completed.append(item)
            write(item, item['installed'])
    except Exception:
        for item in reversed(completed):
            write(item, item['original'])
        raise
    print('macOS backup manifest: ' + str(manifest))
    print('Preferences verified. Existing apps may need reopening or logout to pick them up.')
    return manifest


def restore(document, dry_run=False):
    if document.get('version') != 1 or document.get('kind') != 'macos-preferences':
        raise ValueError('Unsupported macOS backup manifest')
    changes = document['changes']
    for item in changes:
        if current(item) not in (item['original'], item['installed']):
            raise ValueError('Restore would overwrite a later preference edit: ' + item['key'])
    for item in reversed(changes):
        print(('Would restore preference: ' if dry_run else 'Restore preference: ') + item['domain'] + '/' + item['key'])
        if not dry_run:
            write(item, item['original'])
