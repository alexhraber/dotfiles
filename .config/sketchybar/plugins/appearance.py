"""One validated palette shared by SketchyBar, hover controls and the native dock."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

CATALOG = Path(__file__).resolve().parents[1] / 'themes.json'
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'dotfiles/desktop'
LAYOUTS = ('ribbon', 'islands')
TOKENS = ('surface', 'popup', 'border', 'foreground', 'muted', 'accent',
          'secondary', 'highlight', 'selection', 'success', 'warning', 'danger')
PANELS = ('clock', 'weather', 'volume', 'brightness', 'wifi', 'bluetooth', 'alerts', 'battery', 'cpu', 'gpu', 'memory')


def resolve(name=None, layout=None):
    catalog = json.loads(CATALOG.read_text())
    try:
        saved = json.loads((STATE / 'appearance.json').read_text())
    except (OSError, ValueError):
        saved = {}
    name = name or saved.get('name', catalog['default'])
    layout = layout or saved.get('layout', catalog['layout'])
    if name not in catalog['themes'] or layout not in LAYOUTS:
        raise ValueError('Choose graphite, nocturne, tidal, ember or iris; layout ribbon or islands')
    palette = catalog['themes'][name]
    if any(not re.fullmatch(r'[0-9a-fA-F]{6}', palette.get(key, '')) for key in TOKENS):
        raise ValueError('Palette colors must be six hexadecimal digits')
    return dict(palette, name=name, layout=layout)


def color(key, alpha='ff'):
    return '0x' + alpha + resolve()[key]


def shell(palette):
    values = {'UI_' + key.upper(): '0xff' + palette[key] for key in TOKENS}
    values['UI_GLASS'] = '0xeb' + palette['surface']
    values['UI_POPUP_GLASS'] = '0xff' + palette['popup']
    values['UI_HOVER'] = '0xff' + palette['highlight']
    values['UI_LAYOUT'] = palette['layout']
    return '\n'.join(key + '=' + shlex.quote(value) for key, value in values.items()) + '\n'


def save(palette):
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    for name, content in (('appearance.json', json.dumps(palette) + '\n'), ('appearance.sh', shell(palette))):
        path = STATE / name
        temporary = path.with_name(name + '.' + str(os.getpid()))
        temporary.write_text(content)
        temporary.chmod(0o600)
        os.replace(temporary, path)


def apply():
    """Recolor existing items in one IPC call, retaining hover and bar visibility."""
    palette = resolve()
    def c(key, alpha='ff'):
        return '0x' + alpha + palette[key]
    # Apply visibility directly; interpolating boolean drawing properties can
    # leave overlapping bracket backgrounds enabled after a layout switch.
    args = ['sketchybar']
    for group in ('context', 'chronicle', 'ribbon', 'hardware', 'connections', 'session', 'notifications'):
        active = group == 'context' or (group == 'ribbon' and palette['layout'] == 'ribbon') or (
            palette['layout'] == 'islands' and group in ('hardware','connections','chronicle','notifications'))
        args += ['--set', group, 'background.drawing=' + ('on' if active else 'off'),
                 'drawing=' + ('on' if active else 'off'),
                 'background.color=' + c('surface', 'eb'), 'background.border_color=' + c('border')]
    for boundary in ('hardware', 'session', 'chronicle', 'notifications'):
        args += ['--set', 'gap_' + boundary,
                 'drawing=' + ('on' if palette['layout']=='islands' and boundary!='session' else 'off')]
    for panel in PANELS:
        args += ['--set', panel, 'icon.color=' + c('muted'), 'label.color=' + c('foreground')]
    for panel in ('cpu', 'gpu', 'memory'):
        args += ['--set', panel, 'label.color=' + c('muted'), 'icon.color=' + c('secondary')]
    args += ['--set', 'clock', 'label.color=' + c('foreground'),
             '--set', 'weather', 'label.color=' + c('foreground'),
             '--set', 'battery', 'label.color=' + c('foreground'),
             '--set', 'apple', 'icon.color=' + c('accent'),
             '--set', 'front_app', 'label.color=' + c('foreground'),
             '--set', r'/app_menu\..*/', 'label.color=' + c('foreground'),
             '--set', 'clock', 'label.color=' + c('accent'),
             '--set', 'weather', 'icon.color=' + c('secondary'),
             '--set', 'alerts', 'icon.color=' + c('accent')]
    subprocess.run(args, check=True, timeout=5)


if __name__ == '__main__':
    if sys.argv[1:] == ['shell']:
        print(shell(resolve()), end='')
    elif sys.argv[1:] == ['apply']:
        apply()
    else:
        print(json.dumps(resolve()))
