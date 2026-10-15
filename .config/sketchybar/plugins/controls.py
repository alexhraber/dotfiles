"""Hover controls for SketchyBar. Device names and samples stay in private state."""
import calendar
from datetime import date
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys
import time
import appearance

PANELS = appearance.PANELS
HERE = Path(__file__).resolve()
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'dotfiles/desktop/bar'


def brightness(*values):
    return command(str(STATE.parent / 'desktop-edge'), '--brightness', *values)


def command(*args, timeout=5):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=timeout).strip()


def bar(*args):
    command('sketchybar', *args, timeout=3)


def script(*args):
    return shlex.join(['python3', '-B', str(HERE), *map(str, args)])


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
    if name == 'clock':
        offset = read('calendar.json', 0)
        today = date.today()
        month = today.year * 12 + today.month - 1 + offset
        year, index = divmod(month, 12)
        lines = calendar.TextCalendar(firstweekday=0).formatmonth(year, index + 1).splitlines()
        return [(line, None) for line in lines] + [
            ('← Previous month', ['month', str(offset - 1)]),
            ('Today', ['month', '0']), ('Next month →', ['month', str(offset + 1)])]
    if name == 'brightness':
        value = brightness()
        bar('--set', 'brightness.slider', 'slider.percentage=' + value,
            '--set', 'brightness', 'label=' + value + '%')
        return [('Display · ' + value + '%', None), ('Built-in display brightness', None)]
    if name == 'volume':
        volume = command('osascript', '-e', 'output volume of (get volume settings)')
        muted = command('osascript', '-e', 'output muted of (get volume settings)') == 'true'
        bar('--set', 'volume.slider', 'slider.percentage=' + volume)
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
                (state.strip().capitalize(), None)]
        estimate = estimate.replace('present: true', '').strip()
        if estimate:
            rows.append((estimate.capitalize(), None))
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
    if name == 'front_app':
        palette = appearance.resolve()
        return [('Current application', None), ('Show app windows', ['expose']),
                ('Mission Control', ['mission-control']), ('Appearance', None)] + [
                (('● ' if palette['name']==theme else '○ ') + title, ['appearance', '--theme', theme])
                for theme, title in (('tidal','Tidal · petrol / seafoam'), ('ember','Ember · charcoal / copper'), ('iris','Iris · plum / lavender'))] + [
                ('Layout · ' + palette['layout'].title(), ['appearance', '--layout', 'islands' if palette['layout']=='ribbon' else 'ribbon'])]
    metrics = sample()
    if not metrics:
        return [('Waiting for hardware sample…', None)]
    if name == 'memory':
        memory = metrics['memory']
        return [(f'{key.replace("_", " ").title()} · {memory[key]/2**30:.2f} GiB', None)
                for key in ('ram_usage', 'ram_total', 'swap_usage', 'swap_total')]
    return [
        (f'{name.upper()} · {metrics[name + "_scaled_ratio"] * 100:.0f}%', None),
        (f'Temperature · {fahrenheit(metrics["temp"][name + "_temp_avg"]):.1f}°F', None),
        (f'Power · {metrics.get(name + "_power", 0):.1f} W', None),
        (f'System power · {metrics.get("sys_power", 0):.1f} W', None),
    ] + [(f'Fan {i + 1} · {fan["rpm"]:.0f} RPM', None) for i, fan in enumerate(metrics.get('fans', []))]


def show(name):
    token = [time.time_ns(), name]
    store('hover.json', token)
    previous = read('active.json', {})
    delay = 0.06 if time.time()-previous.get('time', 0)<1 else 0.16
    time.sleep(delay)
    if read('hover.json') != token:
        return
    close_panels()
    bar('--animate', 'tanh', '6', '--set', name,
        'background.drawing=on', 'background.color=' + appearance.color('highlight', '66'))
    store('active.json', {'name': name, 'time': time.time()})
    cached = read(name + '.cache.json', {})
    if cached.get('rows'):
        render_rows(name, cached['rows'])
        ttl = 0 if name in ('cpu','gpu','memory','alerts') else 2 if name in ('volume','brightness') else 15
        if time.time()-cached.get('time', 0)<ttl:
            return
    else:
        render_rows(name, [(name.replace('_', ' ').title(), None), ('Loading…', None)])
    rows = fresh_rows(name)
    if read('hover.json') != token:
        return
    render_rows(name, rows)


def fresh_rows(name):
    try:
        rows = panel_rows(name)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        rows = [(name.title(), None), ('Device access is unavailable', None)]
    store(name + '.cache.json', {'time': time.time(), 'rows': rows})
    return rows


def render_rows(name, rows):
    rows = rows[:14]
    store(name + '.json', [action for _, action in rows])
    args = []
    for i in range(14):
        label, action = rows[i] if i < len(rows) else ('', None)
        calendar_grid = name=='clock' and 0<i<8
        font = 'SF Mono:Regular:12.0' if calendar_grid else 'SF Pro:Semibold:13.0' if i==0 else 'SF Pro:Medium:12.0' if action else 'SF Pro:Regular:12.0'
        args += ['--set', f'{name}.row.{i}', 'drawing=' + ('on' if i < len(rows) else 'off'),
                 'label=' + label, 'label.color=' + appearance.color('accent' if action else 'foreground'),
                 'label.font=' + font, 'label.align=' + ('center' if name=='clock' else 'left'),
                 'background.drawing=off',
                 'script=' + (shlex.quote(str(HERE.parent/'status.sh')) if action else ''),
                 'click_script=' + (script('action', name, i) if action else '')]
    args += ['--set', name, 'popup.drawing=on']
    bar(*args)


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
    args = []
    for panel in PANELS:
        args += ['--set', panel, 'popup.drawing=off', 'background.drawing=off']
    bar(*args)


def action(args):
    kind, *values = args
    if kind == 'month':
        store('calendar.json', int(values[0]))
    elif kind == 'mute':
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
    elif kind == 'mission-control':
        command('open', '-a', 'Mission Control')
    elif kind == 'expose':
        # Standard App Exposé; only on an explicit click.
        command('osascript', '-e', 'tell application "System Events" to key code 125 using control down')
    elif kind == 'appearance':
        command(str(HERE.parents[3] / 'scripts/dotfiles'), 'desktop', 'theme', *values, timeout=10)
    else:
        raise ValueError('Unknown control')


def main():
    kind, name, *extra = sys.argv[1:]
    if kind == 'hover' and name in PANELS:
        show(name)
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
        store('hover.json', [time.time_ns(), None])
        close_panels()
    elif kind == 'close':
        token = [time.time_ns(), None]
        store('hover.json', token)
        time.sleep(0.25)
        if read('hover.json') == token:
            close_panels()
    elif kind == 'slider':
        if name in ('volume', 'brightness'):
            action([name, os.environ.get('PERCENTAGE', '0')])
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
    elif kind == 'action' and name in PANELS:
        actions = read(name + '.json', [])
        selected = actions[int(extra[0])]
        if selected:
            try:
                bar('--set', f'{name}.row.{extra[0]}', 'label=Updating…')
                action(selected)
                (STATE / (name+'.cache.json')).unlink(missing_ok=True)
                show(name)
            except (OSError, subprocess.SubprocessError, ValueError):
                bar('--set', f'{name}.row.0', 'label=Action unavailable · check local permissions')


if __name__ == '__main__':
    main()
