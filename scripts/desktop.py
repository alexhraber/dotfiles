"""Explicit macOS desktop lifecycle; configuration installation starts nothing."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import shutil
import subprocess
import time
import importlib.util
import macos_preferences

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location('desktop_appearance', ROOT / '.config/sketchybar/plugins/appearance.py')
appearance = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(appearance)
LABEL = 'local.dotfiles.desktop-edge'
SERVICES = ('felixkratz/formulae/sketchybar',)
PREFERENCES = [
    {'domain': 'NSGlobalDomain', 'key': '_HIHideMenuBar', 'installed': {'type': 'bool', 'value': True}},
    {'domain': 'com.apple.dock', 'key': 'autohide', 'installed': {'type': 'bool', 'value': True}},
    {'domain': 'com.apple.dock', 'key': 'autohide-delay', 'installed': {'type': 'float', 'value': 86400.0}},
]


def state_dir():
    return Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'dotfiles/desktop'


def save(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.chmod(0o600)
    os.replace(temporary, path)


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def compile_tools(directory):
    tools = {}
    for source, name, command in (
        ('desktop-edge.m', 'desktop-edge', ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-framework', 'AppKit', '-framework', 'QuartzCore']),
        ('set-wallpaper.swift', 'wallpaper', ['xcrun', 'swiftc']),
    ):
        path = ROOT / 'scripts' / source
        digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
        target = directory / (name + '-' + digest)
        if not target.is_file():
            temporary = target.with_suffix('.new')
            run(*command, path, '-o', temporary)
            temporary.chmod(0o700)
            os.replace(temporary, target)
        tools[name] = str(target)
    return tools


def service_state():
    result = run('brew', 'services', 'info', '--json', *SERVICES, capture_output=True, text=True)
    values = json.loads(result.stdout)
    if len(values) != len(SERVICES):
        raise ValueError('Cannot read desktop service state')
    return {item['name']: bool(item['loaded']) for item in values}


def agent_path():
    return Path.home() / 'Library/LaunchAgents' / (LABEL + '.plist')


def agent_loaded():
    return subprocess.run(['launchctl', 'print', f'gui/{os.getuid()}/{LABEL}'],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def agent_pid():
    result = subprocess.run(['launchctl', 'print', f'gui/{os.getuid()}/{LABEL}'],
                            capture_output=True, text=True)
    match = re.search(r'^\s*pid = (\d+)$', result.stdout, re.MULTILINE)
    return int(match[1]) if result.returncode == 0 and match else None


def unload():
    pid = agent_pid()
    if agent_loaded():
        run('launchctl', 'bootout', f'gui/{os.getuid()}/{LABEL}')
    # bootout can return before the old process releases its WindowServer
    # connection and lock. Do not race its shutdown against a replacement.
    deadline = time.monotonic() + 7
    while pid and time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)


def write_agent(directory, tools):
    bar = shutil.which('sketchybar')
    if not bar:
        raise ValueError('Install the desktop dependencies first')
    executable = directory / 'desktop-edge'
    changed = not executable.is_symlink() or os.readlink(executable) != tools['desktop-edge']
    temporary = directory / 'desktop-edge.next'
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(tools['desktop-edge'])
    os.replace(temporary, executable)
    document = {
        'Label': LABEL,
        'ProgramArguments': [str(executable), bar, str(directory / 'edge.lock'),
                             str(directory / 'status.json')],
        'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 10,
        'ProcessType': 'Interactive', 'LimitLoadToSessionType': 'Aqua',
        'StandardOutPath': str(directory / 'edge.log'),
        'StandardErrorPath': str(directory / 'edge-error.log'),
    }
    path = agent_path()
    data = plistlib.dumps(document)
    if not path.is_file() or path.read_bytes() != data:
        unload()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(0o600)
    if not agent_loaded():
        (directory / 'status.json').unlink(missing_ok=True)
        run('launchctl', 'bootstrap', f'gui/{os.getuid()}', path)
    elif changed:
        (directory / 'status.json').unlink(missing_ok=True)
        run('launchctl', 'kickstart', '-k', f'gui/{os.getuid()}/{LABEL}')


def wait_healthy(directory):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        try:
            status = json.loads((directory / 'status.json').read_text())
            if status['healthy'] and status['pid'] == agent_pid() and time.time() - status['updated'] < 3:
                return
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(0.2)
    raise ValueError('Desktop helper did not become healthy; see desktop status')


def validate_preferences(document):
    for item in document['preferences']:
        if macos_preferences.current(item) not in (item['installed'], item['original']):
            raise ValueError('Restore would overwrite a later preference edit: ' + item['key'])


def restore_runtime(directory, document):
    # Recover the native menu first, even if a guarded preference restore fails.
    unload()
    run(document['tools']['desktop-edge'], '--restore')
    validate_preferences(document)
    changed = False
    for item in reversed(document['preferences']):
        changed |= item['domain'] == 'com.apple.dock' and macos_preferences.current(item) != item['original']
        macos_preferences.write(item, item['original'])
    if changed:
        run('killall', 'Dock')
    run(document['tools']['wallpaper'], 'restore', directory / 'wallpaper-original.archive')
    for service in reversed(SERVICES):
        if not document['services'][service.rsplit('/', 1)[1]]:
            run('brew', 'services', 'stop', service)
    agent_path().unlink(missing_ok=True)
    document['active'] = False
    save(directory / 'manifest.json', document)
    print('Native menu, wallpaper, and prior Dock/service settings restored. Config and packages retained.')


def main(action, theme=None, layout=None):
    if os.uname().sysname != 'Darwin':
        raise ValueError('Desktop runtime requires macOS')
    directory = state_dir()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    with (directory / 'lifecycle.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        manifest = directory / 'manifest.json'
        document = json.loads(manifest.read_text()) if manifest.exists() else None
        if action in ('apply', 'theme'):
            palette = appearance.resolve(theme, layout)
            if action == 'theme' and (not document or not document['active']):
                raise ValueError('Enable the desktop profile before changing its appearance')
            appearance.save(palette)
            if action == 'theme':
                appearance.apply()
                pid = agent_pid()
                if pid:
                    os.kill(pid, signal.SIGUSR1)
                print('Desktop appearance: ' + palette['name'] + ' / ' + palette['layout'])
                return 0
        if action == 'permissions':
            run('sketchybar', '--trigger', 'desktop_access_check')
            access = directory / 'bar/access.json'
            started = time.time()
            deadline = time.monotonic()+35
            while time.monotonic()<deadline:
                if access.exists():
                    result = json.loads(access.read_text())
                    if result['time']>=started-0.1:
                        if result['available']:
                            print('Native quick-panel Accessibility access is available.')
                            return 0
                        break
                time.sleep(0.2)
            run('open', 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility')
            print('Enable Accessibility for SketchyBar in macOS, and allow System Events Automation when asked.')
            print('These OS approvals stay local. Rerun desktop permissions to verify.')
            return 1
        if action == 'status':
            print('Desktop profile: ' + ('active' if document and document['active'] else 'inactive'))
            status = directory / 'status.json'
            healthy = False
            if status.exists():
                data = json.loads(status.read_text())
                print(json.dumps(data))
                healthy = data['healthy'] and data['pid'] == agent_pid() and time.time() - data['updated'] < 3
            print('LaunchAgent loaded: ' + str(agent_loaded()))
            return 0 if not document or not document['active'] or healthy else 1
        if action == 'undo':
            if document and document['active']:
                restore_runtime(directory, document)
            else:
                tools = document['tools'] if document else compile_tools(directory)
                unload()
                run(tools['desktop-edge'], '--restore')
                print('Native menu restored; desktop profile is inactive.')
            return 0
        tools = compile_tools(directory)
        if not document or not document['active']:
            if agent_path().exists() or agent_loaded():
                raise ValueError('An unowned desktop-edge LaunchAgent exists; refusing to replace it')
            backup = directory / 'wallpaper-original.archive'
            if backup.exists():
                backup.rename(directory / ('wallpaper-' + str(time.time_ns()) + '.archive'))
            run(tools['wallpaper'], 'capture', backup)
            preferences = [dict(item, original=macos_preferences.current(item)) for item in PREFERENCES]
            document = {'version': 1, 'active': True, 'tools': tools,
                        'services': service_state(), 'preferences': preferences}
            save(manifest, document)
        else:
            document['tools'] = tools
            save(manifest, document)
        try:
            for service in SERVICES:
                run('brew', 'services', 'start', service)
            run('sketchybar', '--reload')
            changed = False
            for item in document['preferences']:
                changed |= item['domain'] == 'com.apple.dock' and macos_preferences.current(item) != item['installed']
                macos_preferences.write(item, item['installed'])
            run(tools['wallpaper'], 'set', ROOT / 'assets/wallpapers/storm-geometry.png')
            write_agent(directory, tools)
            wait_healthy(directory)
            if changed:
                run('killall', 'Dock')
        except Exception:
            restore_runtime(directory, document)
            raise
        print('Desktop active. Undo: scripts/dotfiles desktop undo')
        print('Private original settings: ' + str(manifest))
        return 0
