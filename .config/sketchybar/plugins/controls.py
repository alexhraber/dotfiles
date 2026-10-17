"""Hover controls for SketchyBar. Device names and samples stay in private state."""
from contextlib import contextmanager
import fcntl
import json
import math
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
import appearance
import weather

PANELS = appearance.PANELS
HERE = Path(__file__).resolve()
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'dotfiles/desktop/bar'


def brightness(*values):
    return command(str(STATE.parent / 'desktop-edge'), '--brightness', *values)


def native_calendar(action):
    return command(str(STATE.parent / 'desktop-edge'), '--calendar' + ('-' + action if action else ''))


def native_controls(action=''):
    return command(str(STATE.parent / 'desktop-edge'), '--controls' + ('-' + action if action else ''))


def command(*args, timeout=5):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=timeout).strip()


def bar(*args):
    command('sketchybar', *args, timeout=3)


def store(name, value):
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = STATE / (name + '-' + str(os.getpid()))
    temporary.write_text(json.dumps(value))
    temporary.chmod(0o600)
    temporary.replace(STATE / name)


def read(name, fallback=None):
    try:
        return json.loads((STATE / name).read_text())
    except (OSError, ValueError):
        return fallback


@contextmanager
def interaction():
    """Serialize hover state and its IPC commit, never slow device reads/dwell."""
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE / 'interaction.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def wifi_device():
    ports = command('networksetup', '-listallhardwareports')
    match = re.search(r'Hardware Port: (?:Wi-Fi|AirPort)\nDevice: (\S+)', ports)
    if not match:
        raise ValueError('Wi-Fi interface unavailable')
    return match[1]


def sample():
    return read('metrics.json', {})


def fahrenheit(celsius):
    return celsius * 9 / 5 + 32


def alerts(metrics, battery=''):
    messages = []
    for component in ('cpu', 'gpu'):
        temperature = metrics.get('temp', {}).get(component + '_temp_avg', 0)
        if temperature >= 85:
            messages.append(f'{component.upper()} temperature {fahrenheit(temperature):.0f}°F')
    swap = metrics.get('memory', {}).get('swap_usage', 0) / 2**30
    if swap:
        messages.append(f'Swap in use: {swap:.1f} GiB')
    charge = re.search(r'(\d+)%; discharging', battery)
    if charge and int(charge[1]) <= 20:
        messages.append('Battery low: ' + charge[1] + '%')
    return messages


def panel_rows(name):
    """Each row is text plus an optional argv action, never interpolated shell."""
    if name == 'weather':
        return weather.rows(include_hours=False, include_days=False)
    if name == 'clock':
        return [('Calendar', None), ('Native month grid and synced agenda', None)]
    if name == 'brightness':
        value = brightness()
        return [('Display · ' + value + '%', None), ('Built-in display brightness', None)]
    if name == 'volume':
        volume = command('osascript', '-e', 'output volume of (get volume settings)')
        muted = command('osascript', '-e', 'output muted of (get volume settings)') == 'true'
        rows = [('Sound · ' + volume + '%' + (' · muted' if muted else ''), None),
                ('Unmute' if muted else 'Mute', ['mute', 'false' if muted else 'true'])]
        try:
            outputs = [json.loads(line) for line in command('SwitchAudioSource', '-a', '-t', 'output', '-f', 'json').splitlines() if line]
            current = command('SwitchAudioSource', '-c', '-t', 'output')
            rows += [(('● ' if item['name'] == current else '○ ') + item['name'],
                      ['output', item['name']]) for item in outputs]
        except (subprocess.SubprocessError, ValueError, KeyError):
            rows.append(('Audio outputs unavailable', None))
        return rows
    if name == 'wifi':
        device = wifi_device()
        powered = command('networksetup', '-getairportpower', device).endswith('On')
        rows = [('Wi-Fi · ' + ('On' if powered else 'Off'), None),
                ('Turn Wi-Fi ' + ('off' if powered else 'on'), ['wifi', device, 'off' if powered else 'on'])]
        if powered:
            try:
                address = command('ipconfig', 'getifaddr', device)
                rows.append(('Address · ' + address, None))
            except subprocess.SubprocessError:
                rows.append(('No IPv4 connection', None))
            network = command('networksetup', '-getairportnetwork', device)
            if ':' in network:
                rows.append((network.split(':', 1)[1].strip(), None))
            else:
                rows.append(('Network names require macOS location access', None))
        rows.append(('Native Wi-Fi controls', ['native', 'Wi-Fi']))
        return rows
    if name == 'bluetooth':
        powered = command('blueutil', '--power') == '1'
        rows = [('Bluetooth · ' + ('On' if powered else 'Off'), None),
                ('Turn Bluetooth ' + ('off' if powered else 'on'), ['bluetooth-power', 'off' if powered else 'on'])]
        devices = json.loads(command('blueutil', '--paired', '--format', 'json')) if powered else []
        rows += [(('● ' if device.get('connected') else '○ ') + device.get('name', 'Device'),
                  ['bluetooth-device', '--disconnect' if device.get('connected') else '--connect', device['address']])
                 for device in devices]
        if powered and not devices:
            rows.append(('No paired devices', None))
        return rows
    if name == 'battery':
        result = command('pmset', '-g', 'batt')
        match = re.search(r'(\d+)%;\s*([^;]+);?\s*([^\n]*)', result)
        charge, state, estimate = match.groups() if match else ('—', 'Unavailable', '')
        rows = [('Battery · ' + charge + '%', None),
                ('State · ' + state.strip().capitalize(), None)]
        estimate = estimate.replace('present: true', '').strip()
        if estimate:
            rows.append(('Estimate · ' + estimate.capitalize(), None))
        try:
            batteries = plistlib.loads(subprocess.check_output(['ioreg', '-r', '-c', 'AppleSmartBattery', '-a'], timeout=3))
            battery = batteries[0]
            rows += [(f'Cycles · {battery.get("CycleCount", "—")}', None),
                     (f'Temperature · {fahrenheit(battery.get("Temperature", 0) / 100):.1f}°F', None)]
        except (subprocess.SubprocessError, ValueError, IndexError):
            pass
        return rows
    if name == 'alerts':
        messages = alerts(sample(), command('pmset', '-g', 'batt'))
        return [('Notifications', None),
            ('Notification Center', ['native', 'Clock']),
            ('Focus / Control Center', ['native', 'Control Center']),
            ('System health', None)] + [(message, None) for message in messages] + (
                [('All clear', None)] if not messages else [])
    metrics = sample()
    if not metrics:
        return [('Waiting for hardware sample…', None)]
    if name == 'memory':
        memory = metrics['memory']
        return [(f'Memory · {memory["ram_usage"]/2**30:.1f} GiB', None)] + [
            (f'{label} · {memory[key]/2**30:.2f} GiB', None)
            for key, label in (('ram_usage', 'Used'), ('ram_total', 'Total'),
                               ('swap_usage', 'Swap used'), ('swap_total', 'Swap capacity'))]
    return [
        (f'{name.upper()} · {metrics[name + "_scaled_ratio"] * 100:.0f}%', None),
        (f'Temperature · {fahrenheit(metrics["temp"][name + "_temp_avg"]):.1f}°F', None),
        (f'Power · {metrics.get(name + "_power", 0):.1f} W', None),
        (f'System power · {metrics.get("sys_power", 0):.1f} W', None),
    ] + [(f'Fan {i + 1} · {fan["rpm"]:.0f} RPM', None) for i, fan in enumerate(metrics.get('fans', []))]


def item_anchors(name):
    """Snapshot real bar rectangles only in SketchyBar's item event context."""
    if not os.environ.get('NAME'):
        return []
    try:
        rectangles = json.loads(command('sketchybar', '--query', name, timeout=1))['bounding_rects']
        result = []
        for rectangle in list(rectangles.values())[:8]:
            x, y = rectangle['origin']
            width, height = rectangle['size']
            values = (x, y, width, height)
            if not all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and abs(v) <= 100000 for v in values):
                continue
            if (x, y) == (-9999, -9999) or not (0 < width <= 1024 and 0 < height <= 256):
                continue
            result.append(dict(x=x, y=y, width=width, height=height))
        return result
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return []


def show(name, clicked=False):
    token = [time.time_ns(), name]
    with interaction():
        active = read('active.json', {})
        if active.get('request') and active['request'] == read('native-dismissed.json', {}).get('request'):
            active = {}
            store('active.json', active)
        if active.get('pinned') and not clicked:
            return
        if clicked and active.get('name') == name and active.get('pinned'):
            store('hover.json', [time.time_ns(), None])
            close_panels()
            return
        store('hover.json', token)
        store('pin.json', {'request': str(token[0]), 'pinned': clicked and name != 'clock'})
        already_open = active.get('name') == name
    anchors = item_anchors(name) if name != 'clock' else []
    with interaction():
        if read('hover.json') != token:
            return
        store('anchor.json', {'request': str(token[0]), 'anchors': anchors})
    if not already_open and not clicked:
        time.sleep(0.12)
    with interaction():
        if read('hover.json') != token:
            return
        if name == 'clock':
            if not already_open:
                close_panels()
            native_calendar('')
            store('active.json', {'name': name, 'time': time.time()})
            return
    cached = read(name + '.cache.json', {})
    if cached.get('rows'):
        if not render_rows(name, cached['rows'], token):
            return
        ttl = 0 if name in ('cpu','gpu','memory','alerts','weather') else 2 if name in ('volume','brightness') else 15
        if time.time()-cached.get('time', 0)<ttl:
            return
    else:
        if not render_rows(name, [(name.replace('_', ' ').title(), None), ('Loading…', None)], token):
            return
    rows = fresh_rows(name)
    render_rows(name, rows, token)


def leave(item):
    name = item.split('.', 1)[0]
    # Native windows own exit hysteresis and their anchor-to-panel bridge.
    # Cancel a pending open, but retain an open panel while crossing into it.
    with interaction():
        if read('active.json', {}).get('name') != name and read('hover.json', [None, None])[1] == name:
            store('hover.json', [time.time_ns(), None])


def fresh_rows(name):
    try:
        rows = panel_rows(name)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        rows = [(name.title(), None), ('Device access is unavailable', None)]
    store(name + '.cache.json', {'time': time.time(), 'rows': rows})
    return rows


def visible_control(name, token):
    """Require a current request and a fresh native report before refreshing."""
    if not isinstance(token, list) or len(token) != 2 or token[1] != name:
        return False
    request = str(token[0])
    active = read('active.json', {})
    if active.get('name') != name or active.get('request') != request:
        return False
    if read('native-dismissed.json', {}).get('request') == request:
        return False
    try:
        status = json.loads((STATE.parent / 'status.json').read_text())
        if not 0 <= time.time()-status['updated'] < 3:
            return False
        # The native status sample is written once a second. A key pressed
        # immediately after opening must not be lost to the preceding sample.
        if status['updated'] < active['time']:
            return True
        return status['controls']['visible'] is True and status['controls']['name'] == name
    except (OSError, ValueError, KeyError, TypeError):
        return False


def refresh_open(name):
    """System change events update only an open pane; latest request/event wins."""
    if name not in ('volume', 'brightness'):
        return False
    with interaction():
        token = read('hover.json')
        if not visible_control(name, token):
            return False
        event = [time.time_ns(), name, str(token[0])]
        store('device-refresh.json', event)
    try:
        rows = panel_rows(name)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        return False  # Retain the last good slider during transient read failures.
    with interaction():
        if (read('hover.json') != token or read('device-refresh.json') != event
                or not visible_control(name, token)):
            return False
        store(name + '.cache.json', {'time': time.time(), 'rows': rows})
        _render_rows(name, rows)
        return True


def render_rows(name, rows, token=None):
    with interaction():
        if token is not None and read('hover.json') != token:
            return False
        _render_rows(name, rows)
        return True


def _render_rows(name, rows):
    rows = rows[:14]
    store(name + '.json', [action for _, action in rows])
    document = {'name': name, 'revision': str(time.time_ns()), 'request': str(read('hover.json', [0])[0]),
                'rows': [{'text': str(label)[:512], 'action': bool(action)} for label, action in rows]}
    request = document['request']
    anchor = read('anchor.json', {})
    pin = read('pin.json', {})
    document['anchors'] = anchor.get('anchors', []) if anchor.get('request') == request else []
    document['pinned'] = bool(pin.get('pinned')) if pin.get('request') == request else False
    if name == 'weather' and len(rows) > 1 and rows[1][0].startswith('Hourly forecast · '):
        document['rows'][0]['text'] = 'Weather · ' + rows[1][0].split(' · ', 1)[1]
        document['rows'][1]['text'] = rows[0][0]
        document['forecast'] = weather.outlook()
        document['daily'] = weather.daily_outlook()
        document['subtitle'] = str(rows[2][0])[:160] if len(rows) > 2 else ''
    elif name == 'alerts':
        document['rows'][0]['text'] = 'Notifications · Quick controls'
    if name in ('volume', 'brightness') and rows:
        value = re.search(r'(\d+)%', rows[0][0])
        if value:
            document['slider'] = max(0, min(100, int(value[1])))
    history = read('history.json', {}).get(name, [])
    if name in ('cpu', 'gpu', 'memory') and history:
        document['history'] = history[-60:]
    if name in ('cpu', 'gpu', 'memory'):
        document['subtitle'] = 'Unified memory' if name == 'memory' else 'Apple Silicon · utilization'
    if name in ('cpu', 'gpu', 'battery') and rows:
        value = re.search(r' · (\d+(?:\.\d+)?)%', rows[0][0])
        if value:
            document['meter'] = max(0, min(1, float(value[1]) / 100))
    elif name == 'memory':
        memory = sample().get('memory', {})
        used, total = memory.get('ram_usage', 0), memory.get('ram_total', 0)
        if isinstance(used, (int, float)) and isinstance(total, (int, float)) and total > 0 and math.isfinite(used / total):
            document['meter'] = max(0, min(1, used / total))
    store('native-panel.json', document)
    native_controls()
    store('active.json', {'name': name, 'time': time.time(), 'request': request, 'pinned': document['pinned']})


def native_item(title):
    # AXPress opens the native quick panel, not a settings application.
    # TCC requires local Accessibility/Automation approval for SketchyBar.
    selector = {'Clock':'clock', 'Wi-Fi':'wifi', 'Control Center':'controlcenter'}[title]
    applescript = '''
tell application "System Events"
  tell process "ControlCenter"
    set targets to every menu bar item of menu bar 1
    repeat with target in targets
      try
        set identifier to ""
        try
          set identifier to value of attribute "AXIdentifier" of target
        end try
        if identifier contains %s or description of target contains %s then
          click target
          return
        end if
      end try
    end repeat
    error "Control Center item unavailable"
  end tell
end tell
''' % (json.dumps(selector), json.dumps(title))
    command('osascript', '-e', applescript)


def close_panels():
    native_calendar('hide')
    native_controls('hide')
    store('active.json', {})


def native_action(kind, name, value, revision):
    """Reject stale native rows; callbacks carry indices/percentages, never code."""
    with interaction():
        document = read('native-panel.json', {})
        if document.get('name') != name or document.get('revision') != revision:
            return
        if read('active.json', {}).get('name') != name:
            return
        token = read('hover.json')
        if kind == 'native-slider':
            if name not in ('volume', 'brightness') or not math.isfinite(float(value)):
                return
            selected = [name, value]
        else:
            actions = read(name + '.json', [])
            index = int(value)
            if index < 0 or index >= len(actions) or not actions[index]:
                return
            selected = actions[index]
    try:
        action(selected)
        rows = fresh_rows(name)
    except (OSError, subprocess.SubprocessError, ValueError):
        rows = [(name.title(), None), ('Action unavailable · check local permissions', None)]
    render_rows(name, rows, token)


def action(args):
    kind, *values = args
    if kind == 'mute':
        command('osascript', '-e', 'set volume output muted ' + values[0])
    elif kind == 'volume':
        value = max(0, min(100, int(float(values[0]))))
        command('osascript', '-e', f'set volume output volume {value}')
    elif kind == 'brightness':
        brightness(str(max(0, min(100, int(float(values[0]))))))
        fresh_rows('brightness')
    elif kind == 'output':
        command('SwitchAudioSource', '-t', 'output', '-s', values[0])
    elif kind == 'wifi':
        command('networksetup', '-setairportpower', *values)
    elif kind == 'bluetooth-power':
        command('blueutil', '--power', values[0])
    elif kind == 'bluetooth-device':
        command('blueutil', *values)
    elif kind == 'native':
        native_item(values[0])
    elif kind == 'weather-refresh':
        subprocess.Popen([sys.executable,'-B',str(HERE.parent/'weather.py'),'--refresh'],
                         stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    else:
        raise ValueError('Unknown control')


def main():
    kind, name, *extra = sys.argv[1:]
    if kind == 'hover' and name in PANELS:
        show(name)
    elif kind == 'click' and name in PANELS:
        show(name, clicked=True)
    elif kind == 'changed':
        refresh_open(name)
    elif kind == 'leave' and name.split('.', 1)[0] in PANELS:
        leave(name)
    elif kind == 'access':
        if os.environ.get('SENDER')!='desktop_access_check':
            return
        try:
            result = command('osascript', '-e',
                'tell application "System Events" to tell process "ControlCenter" to get value of attribute "AXIdentifier" of every menu bar item of menu bar 1',
                timeout=30)
            store('access.json', {'available': True, 'identifiers': result, 'time': time.time()})
        except (OSError, subprocess.SubprocessError):
            store('access.json', {'available': False, 'time': time.time()})
    elif kind == 'warm':
        from concurrent.futures import ThreadPoolExecutor
        targets = [panel for panel in ('volume', 'brightness', 'wifi', 'bluetooth', 'battery', 'clock')
                   if time.time()-read(panel+'.cache.json', {}).get('time', 0)>15]
        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(fresh_rows, targets))
    elif kind == 'cancel':
        with interaction():
            store('hover.json', [time.time_ns(), None])
            close_panels()
    elif kind in ('native-action', 'native-slider') and name in PANELS and len(extra) == 2:
        native_action(kind, name, *extra)
    elif kind == 'refresh' and name in ('wifi', 'bluetooth'):
        try:
            powered = command('blueutil', '--power') == '1' if name == 'bluetooth' else command(
                'networksetup', '-getairportpower', wifi_device()).endswith('On')
            bar('--set', name, 'icon.color=' + appearance.color('accent' if powered else 'muted'))
        except (OSError, subprocess.SubprocessError, ValueError):
            bar('--set', name, 'icon.color=' + appearance.color('warning'))
    elif kind == 'scroll':
        if name not in ('volume', 'brightness'):
            return
        value = int(brightness() if name == 'brightness' else command('osascript', '-e', 'output volume of (get volume settings)'))
        delta = max(-5, min(5, int(float(os.environ.get('SCROLL_DELTA', '0')))))
        action([name, str(value + delta * 2)])


if __name__ == '__main__':
    main()
