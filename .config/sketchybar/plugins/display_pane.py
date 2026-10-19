"""Real connected displays and native AirPlay/Sidecar choices; no location use."""
import math
import time
import wifi_pane

TOGGLES = {'display-setting-dark-mode': 'Dark Mode',
           'display-setting-night-shift': 'Night Shift',
           'display-setting-true-tone': 'True Tone'}


def query(state, mode='snapshot', selector=None):
    if mode not in ('snapshot', 'action'):
        raise ValueError('Unknown display operation')
    return wifi_pane.query(state, 'display-' + mode, selector)


def validate(value, now=None):
    now = time.time() if now is None else now
    stamp = value.get('sampled')
    if (isinstance(stamp, bool) or not isinstance(stamp, (int, float))
            or not math.isfinite(stamp) or not 0 <= now-stamp < 30):
        raise ValueError('Stale display discovery')
    rows, screens = value.get('rows'), value.get('screens')
    if not isinstance(rows, list) or len(rows) > 32 or not isinstance(screens, list) or len(screens) > 8:
        raise ValueError('Invalid display list')
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError('Invalid display option')
        for key in ('text', 'identifier', 'role', 'page', 'kind'):
            text = row.get(key)
            if (not isinstance(text, str) or not 0 < len(text) <= 512
                    or any(ord(c) < 32 or ord(c) == 127 for c in text)):
                raise ValueError('Invalid display text')
        if not all(isinstance(row.get(key), bool) for key in ('selected', 'enabled')):
            raise ValueError('Invalid display state')
        kind, identifier = row['kind'], row['identifier']
        if kind == 'toggle':
            valid = row['page'] == 'display' and row['role'] == 'AXCheckBox' and TOGGLES.get(identifier) == row['text']
        elif kind == 'device':
            valid = row['page'] == 'mirroring' and row['role'] == 'AXCheckBox' and identifier.startswith('screen-mirroring-device-')
        else:
            valid = kind == 'settings' and row['page'] == 'mirroring' and row['role'] == 'AXButton' and identifier == 'screen-mirroring-preferences'
        if not valid:
            raise ValueError('Unexpected native display control')
    if len({row['identifier'] for row in rows}) != len(rows):
        raise ValueError('Duplicate display action')
    for screen in screens:
        if not isinstance(screen, dict):
            raise ValueError('Invalid connected display')
        if (not isinstance(screen.get('name'), str) or not 0 < len(screen['name']) <= 512
                or any(ord(c) < 32 or ord(c) == 127 for c in screen['name'])
                or screen.get('mode') not in ('Main display', 'Extended display', 'Mirroring', 'Mirror source')):
            raise ValueError('Invalid display metadata')
        for key in ('width', 'height'):
            if type(screen.get(key)) is not int or not 0 < screen[key] <= 32768:
                raise ValueError('Invalid display dimensions')
        refresh = screen.get('refresh', 0)
        if type(refresh) not in (int, float) or not math.isfinite(refresh) or not 0 <= refresh <= 1000:
            raise ValueError('Invalid refresh rate')
    if not isinstance(value.get('handoff', False), bool):
        raise ValueError('Invalid display handoff')
    if not isinstance(value.get('partial', False), bool):
        raise ValueError('Invalid discovery completeness')
    if value.get('partial') and not rows:
        raise ValueError('Empty partial display discovery')
    if not value.get('handoff') and not value.get('partial') and not any(row['kind'] == 'settings' for row in rows):
        raise ValueError('Native display discovery is incomplete')
    return value


def panel_rows(value, brightness):
    value = validate(value)
    if value.get('handoff'):
        raise ValueError('System display confirmation is active')
    rows = [('Display · ' + str(brightness) + '%', None), ('Connected displays', None)]
    screens = value['screens']
    rows += [(screen['name'], None) for screen in screens[:3]]
    if len(screens) > 3:
        rows.append((f'{len(screens)-3} more connected displays', None))
    rows += [(row['text'], ['display-pane', row]) for row in value['rows']
             if row['kind'] == 'toggle' and row['enabled']]
    rows.append(('Mirror or extend to', None))
    devices = [row for row in value['rows'] if row['kind'] == 'device']
    # Reserve a real native Settings action even when discovery returns many TVs.
    room = max(0, 13-len(rows))
    rows += [(row['text'], ['display-pane', row] if row['enabled'] else None) for row in devices[:room]]
    if not devices:
        available = any(row['kind'] == 'settings' for row in value['rows'])
        rows.append(('No nearby displays found' if available else 'Nearby display discovery unavailable', None))
    settings = next((row for row in value['rows'] if row['kind'] == 'settings'), None)
    if settings:
        rows.append(('Display settings…', ['display-pane', settings] if settings['enabled'] else None))
    return rows
