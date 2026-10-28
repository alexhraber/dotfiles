"""Explicit macOS desktop lifecycle; configuration installation starts nothing."""
import fcntl
import ctypes
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
import tempfile
import importlib.util
import macos_preferences

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location('desktop_appearance', ROOT / '.config/sketchybar/plugins/appearance.py')
appearance = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(appearance)
LABEL = 'local.dotfiles.desktop-edge'
BUNDLE_ID = 'local.dotfiles.desktop-controls'
SERVICES = ('felixkratz/formulae/sketchybar',)
PREFERENCES = [
    {'domain': 'NSGlobalDomain', 'key': '_HIHideMenuBar', 'installed': {'type': 'bool', 'value': True}},
    {'domain': 'com.apple.dock', 'key': 'autohide', 'installed': {'type': 'bool', 'value': True}},
    {'domain': 'com.apple.dock', 'key': 'autohide-delay', 'installed': {'type': 'float', 'value': 86400.0}},
    *macos_preferences.desired(ROOT/'.config/macos/overview.json'),
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


def register_bundle(executable):
    """Register the complete helper bundle even when launchd starts its binary."""
    bundle = Path(executable).parents[2]
    cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    ls = ctypes.CDLL('/System/Library/Frameworks/CoreServices.framework/CoreServices')
    cf.CFURLCreateFromFileSystemRepresentation.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_bool]
    cf.CFURLCreateFromFileSystemRepresentation.restype = ctypes.c_void_p
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    ls.LSRegisterURL.argtypes = [ctypes.c_void_p, ctypes.c_bool]
    ls.LSRegisterURL.restype = ctypes.c_int32
    raw = os.fsencode(bundle)
    url = cf.CFURLCreateFromFileSystemRepresentation(None, raw, len(raw), True)
    if not url:
        raise ValueError('Cannot identify Desktop Controls bundle')
    try:
        status = ls.LSRegisterURL(url, True)
        if status:
            raise ValueError(f'Cannot register Desktop Controls bundle: {status}')
    finally:
        cf.CFRelease(url)


def signing_identity(required=False):
    identity = os.environ.get('DOTFILES_SIGNING_IDENTITY', '')
    if not identity:
        try:
            result = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True,
                                             stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            result = ''
        matches = re.findall(r'\b([A-F0-9]{40}) "Apple Development:', result)
        if len(matches) != 1:
            if required:
                raise ValueError('Set DOTFILES_SIGNING_IDENTITY to one local signing identity')
            return '-'
        identity = matches[0]
    return identity


def setup_panels(directory):
    """Build auxiliary panes without changing Desktop Controls or its approvals."""
    identity = signing_identity(required=True)
    sources = ('wifi-pane.m', 'wifi-pane-info.plist', 'control-panel.m', 'control-panel.h',
               'calendar-panel.m', 'calendar-panel.h', 'app-menu.m', 'app-menu.h', 'panel-style.m', 'panel-style.h',
               'workspace-panels.m', 'workspace-panels.h', 'overview-panel.m', 'overview-panel.h', 'panel-request.m', 'panel-request.h')
    digest = hashlib.sha256(identity.encode() + b''.join((ROOT/'scripts'/name).read_bytes() for name in sources)).hexdigest()[:16]
    bundle = directory / ('DesktopPanels-' + digest + '.app')
    target = bundle / 'Contents/MacOS/wifi-pane'
    if not target.is_file():
        with tempfile.TemporaryDirectory(prefix='panels-build-', dir=directory) as temp:
            staged = Path(temp) / 'Desktop Panels.app'
            executable = staged / 'Contents/MacOS/wifi-pane'
            executable.parent.mkdir(parents=True)
            command = ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                       '-mmacosx-version-min=14.0', '-DDF_CONTROL_NOTIFICATION="local.dotfiles.desktop.panels"']
            for framework in ('AppKit', 'QuartzCore', 'EventKit', 'ApplicationServices', 'ScreenCaptureKit', 'SystemConfiguration', 'AVFoundation', 'CoreMedia'):
                command += ['-framework', framework]
            run(*command, *(ROOT/'scripts'/name for name in ('wifi-pane.m', 'control-panel.m', 'calendar-panel.m', 'app-menu.m', 'panel-style.m', 'workspace-panels.m', 'overview-panel.m', 'panel-request.m')), '-o', executable)
            executable.chmod(0o700)
            shutil.copyfile(ROOT/'scripts/wifi-pane-info.plist', staged/'Contents/Info.plist')
            run('codesign', '--force', '--sign', identity, '--identifier', 'local.dotfiles.wifi-pane', staged)
            run('codesign', '--verify', '--strict', staged)
            os.replace(staged, bundle)
    run('codesign', '--verify', '--strict', bundle)
    register_bundle(target)
    link = directory/'wifi-pane'
    if link.is_symlink() and link.resolve() == target:
        return target
    if link.exists() or link.is_symlink():
        backup = Path(tempfile.mkdtemp(prefix='panels-link-', dir=directory))
        backup.chmod(0o700)
        os.replace(link, backup/'wifi-pane')
    temporary = directory/'wifi-pane.new'
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    os.replace(temporary, link)
    return target


def compile_tools(directory, names=None):
    tools = {}
    for source, name, command in (
        ('desktop-edge.m', 'desktop-edge', ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-mmacosx-version-min=14.0', '-framework', 'AppKit', '-framework', 'QuartzCore', '-framework', 'EventKit', '-framework', 'ApplicationServices', '-framework', 'SystemConfiguration']),
        ('set-wallpaper.swift', 'wallpaper', ['xcrun', 'swiftc']),
    ):
        if names is not None and name not in names:
            continue
        path = ROOT / 'scripts' / source
        material = path.read_bytes()
        if name == 'desktop-edge':
            identity = signing_identity()
            material += identity.encode()
            material += b''.join((ROOT / 'scripts' / extra).read_bytes()
                                 for extra in ('calendar-panel.m', 'calendar-panel.h', 'control-panel.m', 'control-panel.h', 'app-menu.m', 'app-menu.h', 'panel-style.m', 'panel-style.h', 'panel-request.m', 'panel-request.h', 'desktop-edge-info.plist', 'overview-gesture.m', 'overview-gesture.h'))
        digest = hashlib.sha256(material).hexdigest()[:16]
        bundle = directory / ('DesktopControls-' + digest + '.app')
        target = bundle / 'Contents/MacOS/desktop-edge' if name == 'desktop-edge' else directory / (name + '-' + digest)
        if not target.is_file():
            if name == 'desktop-edge':
                # Publish a complete signed bundle only after all build steps
                # pass. A failed compiler/signature never becomes the cache.
                with tempfile.TemporaryDirectory(prefix='desktop-build-', dir=directory) as temp:
                    staged = Path(temp) / 'Desktop Controls.app'
                    executable = staged / 'Contents/MacOS/desktop-edge'
                    executable.parent.mkdir(parents=True)
                    run(*command, path, ROOT / 'scripts/calendar-panel.m', ROOT / 'scripts/control-panel.m', ROOT / 'scripts/app-menu.m', ROOT/'scripts/panel-style.m', ROOT/'scripts/panel-request.m', ROOT/'scripts/overview-gesture.m', '-o', executable)
                    executable.chmod(0o700)
                    shutil.copyfile(ROOT / 'scripts/desktop-edge-info.plist', staged / 'Contents/Info.plist')
                    run('codesign', '--force', '--sign', identity, '--identifier', BUNDLE_ID, staged)
                    run('codesign', '--verify', '--strict', staged)
                    os.replace(staged, bundle)
            else:
                temporary = target.with_suffix('.new')
                run(*command, path, '-o', temporary)
                temporary.chmod(0o700)
                os.replace(temporary, target)
        tools[name] = str(target)
    return tools


def controls_access(executable, request=False):
    """Ask the exact staged, registered bundle; never broadcast to an old build."""
    with tempfile.TemporaryDirectory(prefix='controls-access-', dir=state_dir()) as temp:
        output = Path(temp)/'result.json'
        output.touch(mode=0o600)
        args = ['open', '-W', '-n', '-a', str(Path(executable).parents[2]),
                '--stdout', str(output), '--stderr', '/dev/null']
        if not request:
            args += ['-g']
        args += ['--args', '--request-access' if request else '--access-status']
        run(*args, timeout=95, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if output.stat().st_size>4096:
            raise ValueError('Invalid controls access response')
        value = json.loads(output.read_text())
        if not isinstance(value, dict) or not all(isinstance(value.get(key), bool) for key in ('accessibility', 'calendar')):
            raise ValueError('Invalid controls access response')
        return value


def themed_wallpaper(directory, palette):
    tool = compile_tools(directory, names=('wallpaper',))['wallpaper']
    digest = hashlib.sha256((ROOT/'scripts/set-wallpaper.swift').read_bytes()
                            + json.dumps(palette, sort_keys=True).encode()).hexdigest()[:16]
    target = directory/('wallpaper-theme-' + digest + '.png')
    if not target.is_file():
        with tempfile.TemporaryDirectory(prefix='wallpaper-palette-', dir=directory) as temp:
            source = Path(temp)/'palette.json'
            save(source, {key:value for key, value in palette.items() if isinstance(value, str)})
            run(tool, 'render', source, target)
    return tool, target


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


def control_access_ready(directory):
    """Approval belongs to the current helper, not an old status file or host."""
    try:
        status = json.loads((directory / 'status.json').read_text())
        return (status['healthy'] and status['pid'] == agent_pid()
                and 0 <= time.time() - status['updated'] < 3
                and status['app_menus']['accessibility'] == 1)
    except (OSError, ValueError, KeyError, TypeError):
        return False


def extend_preferences(document):
    existing = {(item['domain'], item['key'], tuple(item.get('path', []))) for item in document['preferences']}
    additions = list(PREFERENCES)
    for corner in ('tl', 'tr', 'bl', 'br'):
        item = {'domain': 'com.apple.dock', 'key': 'wvous-' + corner + '-corner'}
        if macos_preferences.current(item) in ({'type': 'int', 'value': n} for n in (2, 3, 4)):
            additions.append(dict(item, installed={'type': 'int', 'value': 1}))
    for item in additions:
        identity = (item['domain'], item['key'], tuple(item.get('path', [])))
        if identity not in existing:
            document['preferences'].append(dict(item, original=macos_preferences.current(item)))
            existing.add(identity)


def reload_overview_preferences():
    run('/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings', '-u')
    run('killall', 'Dock')
    subprocess.run(['killall', 'WindowManager'], check=False)


def validate_preferences(document):
    for item in document['preferences']:
        if macos_preferences.current(item) not in (item['installed'], item['original']):
            raise ValueError('Restore would overwrite a later preference edit: ' + item['key'])


def restore_runtime(directory, document):
    auxiliary = directory/'wifi-pane'
    if auxiliary.is_file():
        run(auxiliary, '--ui-hide')
        run(auxiliary, '--workspace-hide')
    # Recover the native menu first, even if a guarded preference restore fails.
    unload()
    run(document['tools']['desktop-edge'], '--restore')
    validate_preferences(document)
    changed = False
    for item in reversed(document['preferences']):
        changed |= macos_preferences.current(item) != item['original']
        macos_preferences.write(item, item['original'])
    if changed:
        reload_overview_preferences()
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
        prepared_tools = None
        if action in ('controls-setup', 'controls-permissions'):
            target = Path(compile_tools(directory, names=('desktop-edge',))['desktop-edge'])
            register_bundle(target)
            print('Staged Desktop Controls: ' + str(target.parents[2]))
            print('The running helper is retained until desktop apply.')
            if action == 'controls-permissions':
                access = controls_access(target, request=True)
                print(json.dumps(access))
                return 0 if all(access.values()) else 1
            return 0
        if action in ('launcher', 'overview'):
            run(directory/'desktop-edge', '--' + action)
            return 0
        if action in ('panels-setup', 'panels-permissions'):
            target = setup_panels(directory)
            print('Desktop Panels: ' + str(target.parents[2]))
            if action == 'panels-permissions':
                spec = importlib.util.spec_from_file_location('wifi_pane', ROOT/'.config/sketchybar/plugins/wifi_pane.py')
                adapter = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(adapter)
                access = adapter.query(directory/'bar', 'request-access')
                print(json.dumps(access))
                if not access['accessibility']:
                    print('Enable Desktop Panels in Device Control and Data Access (Accessibility), then rerun this command for Screen Recording.')
                elif not access['screen_capture']:
                    print('Enable Desktop Panels in Screen & System Audio Recording, then verify again.')
                return 0 if all(access[key] for key in ('accessibility', 'screen_capture', 'supported')) else 1
            return 0
        if action in ('apply', 'theme'):
            if action == 'apply' and document and document.get('active'):
                prepared_tools = compile_tools(directory)
                candidate = Path(prepared_tools['desktop-edge'])
                current = directory/'desktop-edge'
                if not current.is_symlink() or current.resolve() != candidate:
                    register_bundle(candidate)
                    if not all(controls_access(candidate).values()):
                        raise ValueError('The staged Desktop Controls needs its own Accessibility/Calendar approval. '
                                         'Run desktop controls-permissions before apply. The working helper is retained.')
                    backup = directory/'updates'/str(time.time_ns())
                    backup.mkdir(parents=True, mode=0o700)
                    shutil.copy2(manifest, backup/'manifest.json')
                    if agent_path().is_file():
                        shutil.copy2(agent_path(), backup/'LaunchAgent.plist')
                    if current.is_symlink():
                        (backup/'desktop-edge').symlink_to(current.resolve())
                    if (directory/'appearance.json').is_file():
                        shutil.copy2(directory/'appearance.json', backup/'appearance.json')
                    print('Prior desktop runtime backup: ' + str(backup))
            palette = appearance.resolve(theme, layout)
            if action == 'theme' and (not document or not document['active']):
                raise ValueError('Enable the desktop profile before changing its appearance')
            import manage
            import workstation_theme
            config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home()/'.config'))
            projections = [manage.operation(config/rel, content=content)
                           for rel, content in workstation_theme.render(palette, ROOT).items()]
            manage.apply(projections)
            appearance.save(palette)
            if action == 'theme':
                wallpaper, image = themed_wallpaper(directory, palette)
                run(wallpaper, 'set', image)
                appearance.apply()
                pid = agent_pid()
                if pid:
                    os.kill(pid, signal.SIGUSR1)
                # Only update an existing tmux server; never start one for theming.
                if shutil.which('tmux') and subprocess.run(['tmux', 'has-session'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                    run('tmux', 'source-file', config/'tmux/dotfiles-theme.conf')
                print('Desktop appearance: ' + palette['name'] + ' / ' + palette['layout'])
                return 0
        if action == 'permissions':
            if not agent_loaded():
                raise ValueError('Enable the desktop profile before requesting its permissions')
            run(directory / 'desktop-edge', '--app-menu', 'access')
            deadline = time.monotonic()+35
            while time.monotonic()<deadline:
                if control_access_ready(directory):
                    # Existing windows can retain their pre-consent Space
                    # membership. Recreate them after approval without a build.
                    (directory / 'status.json').unlink(missing_ok=True)
                    run('launchctl', 'kickstart', '-k', f'gui/{os.getuid()}/{LABEL}')
                    wait_healthy(directory)
                    print('Desktop Controls is approved; the desktop helper has been restarted.')
                    return 0
                time.sleep(0.2)
            run('open', 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility')
            print('Enable Desktop Controls in Device Control and Data Access (Accessibility on older macOS).')
            print('Requested app: ' + str((directory / 'desktop-edge').resolve().parents[2]))
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
        tools = prepared_tools or compile_tools(directory)
        register_bundle(tools['desktop-edge'])
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
        extend_preferences(document)
        save(manifest, document)
        try:
            for service in SERVICES:
                run('brew', 'services', 'start', service)
            run('sketchybar', '--reload')
            changed = False
            for item in document['preferences']:
                changed |= macos_preferences.current(item) != item['installed']
                macos_preferences.write(item, item['installed'])
            wallpaper, image = themed_wallpaper(directory, palette)
            run(wallpaper, 'set', image)
            write_agent(directory, tools)
            wait_healthy(directory)
            if changed:
                reload_overview_preferences()
                run('launchctl', 'kickstart', '-k', f'gui/{os.getuid()}/{LABEL}')
                wait_healthy(directory)
        except Exception:
            restore_runtime(directory, document)
            raise
        print('Desktop active. Undo: scripts/dotfiles desktop undo')
        print('Private original settings: ' + str(manifest))
        return 0
