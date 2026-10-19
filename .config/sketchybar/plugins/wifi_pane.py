"""Real native Wi-Fi options; private, permission-gated, memory-only UI capture."""
import json
import fcntl
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time


class NativeError(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__('Native Wi-Fi: ' + code)


def diagnostic(state, mode, code, access=None):
    """Keep fixed failure stages locally, never SSIDs, arguments or screen data."""
    stage = mode if mode in ('status', 'request-access', 'snapshot', 'action') else 'unknown'
    value = {'time': time.time(), 'stage': stage, 'code': code}
    if access is not None:
        value['access'] = {key: access[key] for key in ('accessibility', 'screen_capture', 'supported')}
    temporary = state / ('wifi-diagnostic-' + str(os.getpid()))
    for target in ('wifi-diagnostic.json', 'wifi-diagnostic-'+stage+'.json'):
        try:
            fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, 'w') as output:
                json.dump(value, output)
            temporary.replace(state/target)
        except OSError:
            pass  # Diagnostics must never interrupt device controls.
        finally:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass


def query(state, mode='snapshot', selector=None):
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(state/'wifi-query.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            value = _query(state, mode, selector)
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            code = error.code if isinstance(error, NativeError) else 'adapter_error'
            diagnostic(state, mode, code)
            raise
        access = value if mode in ('status', 'request-access') else None
        code = 'access_unavailable' if access is not None and not all(access[key] for key in ('accessibility', 'screen_capture', 'supported')) else 'ok'
        diagnostic(state, mode, code, access)
        return value


def view_context(state):
    try:
        token = json.loads((state/'hover.json').read_text())
        if (not isinstance(token, list) or len(token) != 2 or token[1] != 'wifi'
                or not isinstance(token[0], int) or isinstance(token[0], bool)):
            return None, False
        try:
            view = json.loads((state/'wifi-view.json').read_text())
        except (OSError, ValueError):
            view = {}
        expanded = isinstance(view, dict) and view.get('request') == str(token[0]) and view.get('expanded') is True
        return token, expanded
    except (OSError, ValueError):
        return None, False


def save_view(state, token, value):
    expanded = any(row['kind'] == 'disclosure' and row['selected'] for row in value['rows'])
    fd, filename = tempfile.mkstemp(prefix='wifi-view-', dir=state)
    temporary = Path(filename)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump({'request': str(token[0]), 'expanded': expanded}, output)
        temporary.replace(state/'wifi-view.json')
    finally:
        temporary.unlink(missing_ok=True)


def _query(state, mode, selector):
    helper = state.parent / 'wifi-pane'
    if not helper.is_file():
        raise ValueError('Wi-Fi adapter is not installed')
    bundle = helper.resolve().parents[2]
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, filename = tempfile.mkstemp(prefix='wifi-result-', dir=state)
    os.close(fd)
    result = Path(filename)
    token, expanded = view_context(state) if mode in ('snapshot', 'action') else (None, False)
    try:
        args = ['/usr/bin/open', '-W', '-n', '-a', str(bundle), '--stdout', filename,
                '--stderr', '/dev/null']
        if mode != 'request-access':
            args += ['-g']
        args += ['--args', '--' + mode]
        if selector is not None:
            args += [json.dumps(selector, ensure_ascii=False)]
        if expanded:
            args += ['--expanded']
        process = subprocess.run(args, check=False, timeout=95 if mode == 'request-access' else 15,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.stat().st_size > 131072:
            raise ValueError('Wi-Fi response too large')
        value = json.loads(result.read_text())
        if not isinstance(value, dict):
            raise NativeError('invalid_response')
        if value.get('error'):
            code = value['error']
            known = ('access_unavailable', 'native_panel_busy', 'cover_unavailable', 'native_panel_unavailable',
                     'option_changed', 'action_failed', 'action_no_change', 'input_unavailable', 'invalid_action', 'invalid_mode')
            raise NativeError(code if code in known else 'helper_error')
        if process.returncode:
            raise NativeError('helper_exit')
        if mode in ('status', 'request-access'):
            if not all(isinstance(value.get(key), bool) for key in ('accessibility', 'screen_capture', 'supported')):
                raise ValueError('Invalid Wi-Fi access response')
            return value
        value = validate(value)
        if token is not None and not value.get('handoff') and view_context(state)[0] == token:
            save_view(state, token, value)
        return value
    finally:
        result.unlink(missing_ok=True)


def validate(value, now=None):
    now = time.time() if now is None else now
    stamp = value.get('sampled')
    if (not isinstance(stamp, (int, float)) or isinstance(stamp, bool)
            or not math.isfinite(stamp) or not 0 <= now - stamp < 8):
        raise ValueError('Stale Wi-Fi response')
    rows = value.get('rows')
    if not isinstance(rows, list) or len(rows) > 96:
        raise ValueError('Invalid native Wi-Fi options')
    kinds = ('power', 'network', 'section', 'disclosure', 'button')
    for row in rows:
        if not isinstance(row, dict) or row.get('kind') not in kinds:
            raise ValueError('Invalid native Wi-Fi option')
        for key in ('text', 'role', 'identifier'):
            text = row.get(key)
            if not isinstance(text, str) or len(text) > 512 or any(ord(c) < 32 or ord(c) == 127 for c in text):
                raise ValueError('Invalid native Wi-Fi text')
        if not row['text'] or not all(isinstance(row.get(key), bool) for key in ('selected', 'enabled')):
            raise ValueError('Invalid native Wi-Fi state')
        if row['kind'] == 'network' and not 0 < len(row['text'].encode('utf-8')) <= 32:
            raise ValueError('Invalid network name')
    if not isinstance(value.get('handoff', False), bool):
        raise ValueError('Invalid native Wi-Fi handoff')
    powers = sum(row['kind'] == 'power' for row in rows)
    if powers > 1 or (powers != 1 and not value.get('handoff')):
        raise ValueError('Wi-Fi radio state is missing')
    return value


def panel_rows(value, budget=14):
    """Use Bluetooth's connected-first list, backed by real native actions."""
    value = validate(value)
    if value.get('handoff'):
        raise ValueError('Native Wi-Fi handed off to system controls')
    native = value['rows']
    power = next(row for row in native if row['kind'] == 'power')
    result = [('Wi-Fi · ' + ('On' if power['selected'] else 'Off'), ['wifi-pane', power])]
    networks = [row for row in native if row['kind'] == 'network']
    connected = [row for row in networks if row['selected']]
    split = next((i for i, row in enumerate(native) if row['kind'] == 'disclosure'), len(native))
    nearby = [row for row in native[:split] if row['kind'] == 'network' and not row['selected']][:3]
    options = []
    for row in native:
        if row['kind'] in ('disclosure', 'button'):
            options.append(row)
            if row['kind'] == 'disclosure' and row['selected']:
                options += [item for item in native[split+1:] if item['kind'] == 'network' and not item['selected']][:3]
    body = connected + nearby + options
    # Preserve native buttons and the connected network when the fixed-size
    # renderer's budget is exceeded; only extra network choices are trimmed.
    while len(body) > budget - 1:
        index = next((i for i in range(len(body)-1, -1, -1)
                      if body[i]['kind'] == 'network' and not body[i]['selected']), None)
        if index is None:
            raise ValueError('Native Wi-Fi controls exceed pane capacity')
        body.pop(index)
    result += [(row['text'], ['wifi-pane', row] if row['kind'] != 'section' and row['enabled'] else None)
               for row in body]
    return result


def counters(output, device):
    lines = output.splitlines()
    header = lines[0].split() if lines else []
    try:
        incoming, outgoing = header.index('Ibytes'), header.index('Obytes')
        for line in lines[1:]:
            fields = line.split()
            if fields and fields[0].rstrip('*') == device and len(fields) > max(incoming, outgoing) and fields[2].startswith('<Link#'):
                values = int(fields[incoming]), int(fields[outgoing])
                if min(values) >= 0:
                    return values
    except (ValueError, IndexError):
        pass
    raise ValueError('Wi-Fi interface counters unavailable')


def rates(previous, device, incoming, outgoing, now):
    current = {'device': device, 'incoming': incoming, 'outgoing': outgoing, 'time': now}
    try:
        elapsed = now - previous['time']
        received = incoming - previous['incoming']
        sent = outgoing - previous['outgoing']
        valid = (previous['device'] == device and 0 < elapsed <= 10 and min(received, sent) >= 0)
    except (KeyError, TypeError):
        valid = False
    return current, (received / elapsed, sent / elapsed) if valid else None


def speed(value):
    for unit in ('B/s', 'KB/s', 'MB/s', 'GB/s'):
        if value < 1000 or unit == 'GB/s':
            return f'{value:.1f} {unit}' if unit != 'B/s' else f'{value:.0f} {unit}'
        value /= 1000


def speed_label(values):
    return '↓ —   ↑ —' if values is None else '↓ ' + speed(values[0]) + '   ↑ ' + speed(values[1])
