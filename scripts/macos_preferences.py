"""Per-key macOS preferences, with typed backups and guarded restoration."""
from datetime import datetime
import json
import copy
import ctypes
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
    value = values.get(item['key'])
    if value is None:
        return None
    for key in item.get('path', []):
        if not isinstance(value, dict):
            raise ValueError('Unsupported nested preference container')
        value = value.get(key)
        if value is None:
            return None
    return typed(value) if value is not None else None


def desired(source):
    items = []
    def visit(domain, key, value, path):
        if isinstance(value, dict):
            for child, setting in value.items():
                visit(domain, key, setting, path + [child])
        else:
            if isinstance(value, str) and value.startswith('~/'):
                value = str(Path(value).expanduser())
            item = {'domain': domain, 'key': key, 'installed': typed(value)}
            if path:
                item['path'] = path
            items.append(item)
    for domain, settings in json.loads(Path(source).read_text()).items():
        for key, value in settings.items():
            visit(domain, key, value, [])
    return items


def plan(source):
    changes = []
    for item in desired(source):
        item['original'] = current(item)
        if item['original'] != item['installed']:
            changes.append(item)
    return changes


def write_nested(item, value):
    # CFPreferences updates one root key, preserving every unrelated binding.
    # The manifest guards/restores just the scalar leaf we own.
    root = copy.deepcopy(read_domain(item['domain']).get(item['key'], {}))
    branch = root
    for key in item['path'][:-1]:
        branch = branch.setdefault(key, {})
    leaf = item['path'][-1]
    if value is None:
        branch.pop(leaf, None)
        parents = [root]
        cursor = root
        for name in item['path'][:-1]:
            cursor = cursor[name]
            parents.append(cursor)
        for parent, name in reversed(list(zip(parents, item['path'][:-1]))):
            if not parent[name]:
                del parent[name]
    else:
        branch[leaf] = value['value']
    cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    cf.CFDataCreate.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long]
    cf.CFDataCreate.restype = ctypes.c_void_p
    cf.CFPropertyListCreateWithData.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p, ctypes.c_void_p]
    cf.CFPropertyListCreateWithData.restype = ctypes.c_void_p
    cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
    cf.CFStringCreateWithCString.restype = ctypes.c_void_p
    cf.CFPreferencesSetAppValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    cf.CFPreferencesAppSynchronize.argtypes = [ctypes.c_void_p]
    cf.CFPreferencesAppSynchronize.restype = ctypes.c_bool
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    raw = plistlib.dumps(root)
    data = cf.CFDataCreate(None, raw, len(raw))
    obj = cf.CFPropertyListCreateWithData(None, data, 0, None, None)
    key = cf.CFStringCreateWithCString(None, item['key'].encode(), 0x08000100)
    domain = cf.CFStringCreateWithCString(None, item['domain'].encode(), 0x08000100)
    try:
        if not all((data, obj, key, domain)):
            raise ValueError('Cannot encode nested preference')
        cf.CFPreferencesSetAppValue(key, obj if root else None, domain)
        if not cf.CFPreferencesAppSynchronize(domain):
            raise ValueError('Cannot synchronize nested preference')
    finally:
        for pointer in (data, obj, key, domain):
            if pointer:
                cf.CFRelease(pointer)


def write(item, value):
    prefix = ['defaults']
    if item.get('path'):
        write_nested(item, value)
    elif value is None:
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
