"""On-demand Wi-Fi names. Only explicit opt-in may request OS permission."""
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time


def valid_ssid(value):
    return (isinstance(value, str) and 0 < len(value.encode('utf-8')) <= 32
            and not any(ord(c) < 32 or ord(c) == 127 for c in value))


def validate(value):
    if not isinstance(value, dict) or value.get('authorization') not in (
            'authorized', 'notDetermined', 'denied', 'restricted', 'notInstalled'):
        raise ValueError('Invalid Wi-Fi authorization response')
    if value['authorization'] != 'authorized' or value.get('services') is not True:
        return dict(value, ssid='', networks=[])
    stamp = value.get('sampled')
    if (not isinstance(stamp, (int, float)) or isinstance(stamp, bool)
            or not math.isfinite(stamp) or not 0 <= time.time()-stamp < 15):
        raise ValueError('Wi-Fi sample is stale')
    ssid = value.get('ssid', '')
    if ssid and not valid_ssid(ssid):
        raise ValueError('Invalid connected network')
    networks = value.get('networks')
    if not isinstance(networks, list) or len(networks) > 512:
        raise ValueError('Invalid network list')
    for row in networks:
        if (not isinstance(row, dict) or not valid_ssid(row.get('ssid'))
                or not isinstance(row.get('rssi'), int) or isinstance(row['rssi'], bool)
                or not -128 <= row['rssi'] <= 0 or type(row.get('known')) is not bool
                or type(row.get('secure')) is not bool):
            raise ValueError('Invalid network row')
    return value


def query(state, *, scan=False, request_access=False):
    helper = state.parent / 'wifi-access'
    if not helper.is_file():
        return {'authorization': 'notInstalled', 'services': False, 'ssid': '', 'networks': []}
    mode = '--request-access' if request_access else '--scan' if scan else '--status'
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, filename = tempfile.mkstemp(prefix='wifi-result-', dir=state)
    os.close(descriptor)
    try:
        # LaunchServices establishes the Wi-Fi bundle's own permission identity.
        # Background status/scan launches do not activate an app or request access.
        command = ['/usr/bin/open', '-W', '-n', '-a', str(helper.resolve().parents[2]),
                   '--stdout', filename, '--stderr', '/dev/null']
        if not request_access:
            command.append('-g')
        subprocess.run(command + ['--args', mode], check=True, timeout=70 if request_access else 12,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return validate(json.loads(Path(filename).read_text()))
    finally:
        Path(filename).unlink(missing_ok=True)


def choices(snapshot, recent, now=None):
    """Availability is scan-derived; history only ranks the available set."""
    now = time.time() if now is None else now
    recent = recent if isinstance(recent, dict) else {}
    unique = {}
    for row in snapshot.get('networks', []):
        name = row['ssid']
        if name == snapshot.get('ssid'):
            continue
        if name not in unique or row['rssi'] > unique[name]['rssi']:
            unique[name] = row
    def rank(row):
        used = recent.get(row['ssid'], 0)
        if (not isinstance(used, (int, float)) or isinstance(used, bool)
                or not math.isfinite(used) or not 0 <= used <= now):
            used = 0
        return (not (used or row['known']), -used, -row['rssi'], row['ssid'])
    return sorted(unique.values(), key=rank)[:3]


def current_scan(snapshot, status, invalidated=0, now=None):
    now = time.time() if now is None else now
    try:
        return (status.get('authorization') == snapshot.get('authorization') == 'authorized'
                and status.get('services') is True and snapshot.get('services') is True
                and snapshot.get('interface') == status.get('interface')
                and snapshot.get('ssid') == status.get('ssid')
                and not snapshot.get('error')
                and invalidated <= snapshot['sampled'] <= now
                and now-snapshot['sampled'] < 8)
    except (KeyError, TypeError):
        return False
