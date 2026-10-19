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
import wifi_pane

PANELS = appearance.PANELS
HERE = Path(__file__).resolve()
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'dotfiles/desktop/bar'


def brightness(*values):
    return command(str(STATE.parent / 'desktop-edge'), '--brightness', *values)


def native_calendar(action):
    return command(str(STATE.parent / 'desktop-edge'), '--calendar' + ('-' + action if action else ''))


def native_controls(action=''):
    helper = STATE.parent / 'wifi-pane'
    name = read('native-panel.json', {}).get('name')
    if not action and name in ('wifi', 'bluetooth') and helper.is_file():
        command(str(STATE.parent / 'desktop-edge'), '--controls-hide')
        subprocess.Popen(['/usr/bin/open', '-g', '-n', '-a', str(helper.resolve().parents[2]), '--args', '--ui'],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return ''
    if helper.is_file():
        command(str(helper), '--ui-hide')
    result = command(str(STATE.parent / 'desktop-edge'), '--controls' + ('-' + action if action else ''))
    return result


def start_wifi_watch(request):
    subprocess.Popen([sys.executable, '-B', str(HERE), 'wifi-watch', str(request)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wifi_watch(request):
    token = [int(request), 'wifi']
    next_scan = time.monotonic() + 4
    while visible_control('wifi', token):
        try:
            if time.monotonic() >= next_scan:
                snapshot = wifi_pane.query(STATE)
                with interaction():
                    if not visible_control('wifi', token):
                        return
                    store('wifi-snapshot.json', snapshot)
                next_scan = time.monotonic() + 4
            device = wifi_device()
            incoming, outgoing = wifi_pane.counters(command('/usr/sbin/netstat', '-ibn', '-I', device), device)
            with interaction():
                if not visible_control('wifi', token):
                    return
                current, values = wifi_pane.rates(read('wifi-rates.json', {}), device, incoming, outgoing, time.monotonic())
                store('wifi-rates.json', current)
                store('wifi-speed.json', {'label': wifi_pane.speed_label(values), 'request': str(token[0])})
            refresh_open('wifi')
        except (OSError, subprocess.SubprocessError, ValueError):
            with interaction():
                if read('hover.json') != token:
                    return
                close_panels()
                native_item('Wi-Fi', ensure='open')
                store('active.json', {'name': 'wifi', 'request': str(token[0]), 'time': time.time(), 'native_wifi': True})
            return
        for _ in range(10):
            time.sleep(.1)
            if not visible_control('wifi', token):
                return


def command(*args, timeout=5, strip=True):
    result = subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=timeout)
    return result.strip() if strip else result


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
            rows.append(('Output devices', None))
            rows += [(('● ' if item['name'] == current else '○ ') + item['name'],
                      ['output', item['name']]) for item in outputs]
        except (subprocess.SubprocessError, ValueError, KeyError):
            rows.append(('Audio outputs unavailable', None))
        return rows
    if name == 'wifi':
        status_rows = []
        pending = read('wifi-pending.json', {})
        selected = next((row['text'] for row in read('wifi-snapshot.json', {}).get('rows', [])
                         if row['kind'] == 'network' and row['selected']), '')
        if pending.get('ssid') == selected:
            store('wifi-pending.json', {})
        elif pending.get('ssid') and 0 <= time.time() - pending.get('time', 0) < 20:
            status_rows.append(('Connecting · ' + pending['ssid'], None))
        elif pending.get('ssid'):
            store('wifi-pending.json', {})
            store('wifi-error.json', {'text': 'Connection not established · try again', 'time': time.time()})
        error = read('wifi-error.json', {})
        if 0 <= time.time() - error.get('time', 0) < 8:
            status_rows.append((error['text'], None))
        rows = wifi_pane.panel_rows(read('wifi-snapshot.json', {}), budget=14-len(status_rows))
        rows[1:1] = status_rows
        return rows
    if name == 'bluetooth':
        powered = command('blueutil', '--power') == '1'
        rows = [('Bluetooth · ' + ('On' if powered else 'Off'), ['bluetooth-power', 'off' if powered else 'on'])]
        devices = json.loads(command('blueutil', '--paired', '--format', 'json')) if powered else []
        devices.sort(key=lambda device: (not bool(device.get('connected')), device.get('name', '').casefold()))
        rows += [(('Disconnect ' if device.get('connected') else 'Connect ') + device.get('name', 'Device'),
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
        if hidden_pin(active):
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
    themed_wifi = name == 'wifi' and wifi_pane.available(STATE)
    if themed_wifi:
        try:
            snapshot = wifi_pane.query(STATE)
        except (OSError, subprocess.SubprocessError, ValueError):
            themed_wifi = False
    with interaction():
        if read('hover.json') != token:
            return
        if name == 'wifi':
            if themed_wifi:
                close_native_wifi()
                store('wifi-snapshot.json', snapshot)
                store('wifi-rates.json', {})
                store('wifi-speed.json', {'label': '↓ —   ↑ —', 'request': str(token[0])})
                _render_rows('wifi', panel_rows('wifi'))
                start_wifi_watch(token[0])
                return
            # Apple can display real SSIDs with Location off. Open that picker
            # directly, without flashing a custom loading/permission pane first.
            native_calendar('hide')
            native_controls('hide')
            native_item('Wi-Fi', ensure='open')
            store('active.json', {'name': name, 'time': time.time(),
                                  'request': str(token[0]), 'native_wifi': True})
            return
        if name == 'clock':
            if not already_open:
                close_panels()
            native_calendar('')
            store('active.json', {'name': name, 'time': time.time()})
            return
    cached = {} if name == 'wifi' else read(name + '.cache.json', {})
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


def hidden_pin(active):
    """A fresh native hidden report releases a pin after a Space transition."""
    if not active.get('pinned'):
        return False
    try:
        if active.get('backend') == 'panel-ui':
            status = read('panel-ui-status.json', {})
            return (status.get('request') == active.get('request') and status.get('visible') is False
                    and active['time'] <= status['updated'] <= time.time() and time.time()-status['updated'] < 3)
        status = json.loads((STATE.parent / 'status.json').read_text())
        stamp = status['updated']
        # A preceding sample must not cancel a pin still being opened.
        return (status.get('healthy') is True and 0 <= time.time()-stamp < 3
                and stamp >= active['time'] and status['controls']['visible'] is False)
    except (OSError, ValueError, KeyError, TypeError):
        return False


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
    if active.get('native_wifi'):
        return False  # Apple owns updates; never replace it with a custom pane.
    if read('native-dismissed.json', {}).get('request') == request:
        return False
    try:
        if active.get('backend') == 'panel-ui':
            status = read('panel-ui-status.json', {})
            if status.get('request') != request:
                return time.time()-active['time'] < 2
            return 0 <= time.time()-status['updated'] < 3 and status['visible'] and status['name'] == name
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
    if name not in ('volume', 'brightness', 'wifi'):
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
    close_native_wifi()
    rows = rows[:14]
    store(name + '.json', [action for _, action in rows])
    document = {'name': name, 'revision': str(time.time_ns()), 'request': str(read('hover.json', [0])[0]),
                'rows': [{'text': str(label)[:512], 'action': bool(action)} for label, action in rows]}
    for row, (label, action) in zip(document['rows'], rows):
        if name == 'volume' and label == 'Output devices' and not action:
            row['section'] = True
        elif action and action[0] == 'output':
            row['text'] = str(action[1])[:512]
            row['selected'] = label.startswith('● ')
            row['detail'] = 'Current output' if row['selected'] else ''
            row['hint'] = 'Use output'
        elif action and action[0] == 'bluetooth-device':
            connected = action[1] == '--disconnect'
            row['text'] = label.removeprefix('Disconnect ' if connected else 'Connect ')[:512]
            row['selected'] = connected
            row['detail'] = 'Connected' if connected else 'Not connected'
            row['hint'] = 'Disconnect' if connected else 'Connect'
        elif name == 'wifi' and action and action[0] == 'wifi-pane':
            selector = action[1]
            if selector['kind'] == 'network':
                row['selected'] = selector['selected']
                row['detail'] = 'Connected' if selector['selected'] else ''
                row['hint'] = 'Disconnect' if selector['selected'] else 'Connect'
            elif selector['kind'] == 'disclosure':
                row['hint'] = 'Hide networks' if selector['selected'] else 'Show networks'
        elif name == 'wifi' and not action:
            native = read('wifi-snapshot.json', {}).get('rows', [])
            row['section'] = any(item['kind'] == 'section' and item['text'] == label for item in native)
    request = document['request']
    anchor = read('anchor.json', {})
    pin = read('pin.json', {})
    document['anchors'] = anchor.get('anchors', []) if anchor.get('request') == request else []
    document['pinned'] = bool(pin.get('pinned')) if pin.get('request') == request else False
    if name == 'wifi':
        speed = read('wifi-speed.json', {})
        document['subtitle'] = speed.get('label', '↓ —   ↑ —') if speed.get('request') == request else '↓ —   ↑ —'
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
    backend = 'panel-ui' if name in ('wifi', 'bluetooth') and (STATE.parent / 'wifi-pane').is_file() else 'desktop-edge'
    store('active.json', {'name': name, 'time': time.time(), 'request': request, 'pinned': document['pinned'], 'backend': backend})


def native_item(title, press=True, ensure=None):
    # macOS 27 hosts status extras below MenuBarAgent's hosting views.
    # Earlier systems expose them directly through ControlCenter's menu bar.
    # Only fixed item identifiers are matched; no network list is read here.
    selector = {'Clock':'clock', 'Wi-Fi':'wifi', 'Control Center':'controlcenter'}[title]
    applescript = """
property remaining : 120
on findItem(nodes, wanted, depth, shouldPress)
  if depth > 6 then return false
  tell application "System Events"
    repeat with target in nodes
      set remaining to remaining - 1
      if remaining < 0 then return false
      try
        if (value of attribute "AXIdentifier" of target) is wanted then
          if shouldPress then perform action "AXPress" of target
          return true
        end if
      end try
      try
        if my findItem(UI elements of target, wanted, depth + 1, shouldPress) then return true
      end try
    end repeat
  end tell
  return false
end findItem
%s
tell application "System Events"
  set nodes to {}
  if exists process "MenuBarAgent" then set nodes to UI elements of process "MenuBarAgent"
end tell
if findItem(nodes, %s, 0, %s) then return
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
          if %s then click target
          return
        end if
      end try
    end repeat
    error "System menu item unavailable"
  end tell
end tell
""" % (wifi_visibility_guard(ensure) if title == 'Wi-Fi' and ensure else '',
       json.dumps('com.apple.menuextra.' + selector), 'true' if press else 'false',
       json.dumps(selector), json.dumps(title), 'true' if press else 'false')
    return command('osascript', '-e', applescript)


def wifi_visibility_guard(action):
    """Only toggle Wi-Fi when needed; never dismiss a different system panel."""
    if action not in ('open', 'close'):
        raise ValueError('Unknown Wi-Fi panel action')
    return """
set wifiVisible to false
tell application "System Events"
  if exists process "ControlCenter" then
    set wifiWindows to windows of process "ControlCenter"
    repeat with wifiWindow in wifiWindows
      set remaining to 160
      if my findItem({wifiWindow}, "wifi-header", 0, false) then
        set wifiVisible to true
        exit repeat
      end if
    end repeat
  end if
end tell
if wifiVisible is %s then return
set remaining to 120
""" % ('true' if action == 'open' else 'false')


def close_native_wifi():
    if read('active.json', {}).get('native_wifi'):
        native_item('Wi-Fi', ensure='close')
        store('active.json', {})


def close_panels():
    close_native_wifi()
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
        handoff = selected[0] == 'native'
        if handoff:
            with interaction():
                if read('hover.json') != token:
                    return
                close_panels()
        action(selected)
        if handoff:
            with interaction():
                if read('hover.json') == token:
                    store('hover.json', [time.time_ns(), None])
            return
        rows = fresh_rows(name)
    except (OSError, subprocess.SubprocessError, ValueError):
        if handoff:
            # The hidden request was acknowledged by native code. A failure
            # needs a fresh request, but must never replace a newer interaction.
            with interaction():
                if read('hover.json') != token:
                    return
                previous = read('anchor.json', {})
                token = [time.time_ns(), name]
                store('hover.json', token)
                store('pin.json', {'request': str(token[0]), 'pinned': True})
                store('anchor.json', {'request': str(token[0]), 'anchors': previous.get('anchors', [])})
            rows = fresh_rows(name)
            rows.insert(1, ('System controls unavailable · check Accessibility', None))
        elif name == 'wifi':
            store('wifi-error.json', {'text': 'Connection action unavailable · try again', 'time': time.time()})
            rows = fresh_rows(name)
        else:
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
    elif kind == 'wifi-pane':
        selector = values[0]
        token = read('hover.json')
        if selector['kind'] == 'network' and not selector['selected']:
            store('wifi-pending.json', {'ssid': selector['text'], 'time': time.time()})
            refresh_open('wifi')
        try:
            snapshot = wifi_pane.query(STATE, 'action', selector)
        except (OSError, subprocess.SubprocessError, ValueError):
            store('wifi-pending.json', {})
            raise
        with interaction():
            if read('hover.json') != token:
                return
            store('wifi-snapshot.json', snapshot)
        if snapshot.get('handoff'):
            with interaction():
                store('hover.json', [time.time_ns(), None])
                close_panels()
            return
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
    elif kind == 'wifi-watch':
        wifi_watch(name)
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
            native_item('Control Center', press=False)
            store('access.json', {'available': True, 'time': time.time()})
        except (OSError, subprocess.SubprocessError):
            store('access.json', {'available': False, 'time': time.time()})
    elif kind == 'warm':
        from concurrent.futures import ThreadPoolExecutor
        targets = [panel for panel in ('volume', 'brightness', 'bluetooth', 'battery', 'clock')
                   if time.time()-read(panel+'.cache.json', {}).get('time', 0)>15]
        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(fresh_rows, targets))
    elif kind == 'cancel':
        with interaction():
            if (os.environ.get('SENDER') == 'desktop_concealed'
                    and read('active.json', {}).get('native_wifi')):
                return  # Let the system picker remain usable below the hidden bar.
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
