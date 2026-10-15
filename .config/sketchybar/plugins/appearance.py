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
          'secondary', 'highlight', 'success', 'warning', 'danger')
PANELS = ('clock', 'weather', 'volume', 'brightness', 'wifi', 'bluetooth', 'alerts', 'battery', 'cpu', 'gpu', 'memory', 'front_app')


def resolve(name=None, layout=None):
    catalog = json.loads(CATALOG.read_text())
    try:
        saved = json.loads((STATE / 'appearance.json').read_text())
    except (OSError, ValueError):
        saved = {}
    name = name or saved.get('name', catalog['default'])
    layout = layout or saved.get('layout', catalog['layout'])
    if name not in catalog['themes'] or layout not in LAYOUTS:
        raise ValueError('Choose tidal, ember or iris; layout ribbon or islands')
    palette = catalog['themes'][name]
    if any(not re.fullmatch(r'[0-9a-fA-F]{6}', palette.get(key, '')) for key in TOKENS):
        raise ValueError('Palette colors must be six hexadecimal digits')
    return dict(palette, name=name, layout=layout)


def color(key, alpha='ff'):
    return '0x' + alpha + resolve()[key]


def shell(palette):
    values = {'UI_' + key.upper(): '0xff' + palette[key] for key in TOKENS}
    values['UI_GLASS'] = '0xeb' + palette['surface']
    values['UI_POPUP_GLASS'] = '0xf7' + palette['popup']
    values['UI_HOVER'] = '0x66' + palette['highlight']
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
    args = ['sketchybar', '--animate', 'tanh', '12']
    for group in ('context', 'ribbon', 'hardware', 'connections', 'session', 'notifications'):
        active = group == 'context' or (group == 'ribbon') == (palette['layout'] == 'ribbon')
        args += ['--set', group, 'background.drawing=' + ('on' if active else 'off'),
                 'background.color=' + c('surface', 'eb'), 'background.border_color=' + c('border')]
    for panel in PANELS:
        args += ['--set', panel, 'icon.color=' + c('accent'), 'label.color=' + c('foreground'),
                 'popup.background.color=' + c('popup', 'f7'), 'popup.background.border_color=' + c('border')]
        try:
            actions = json.loads((STATE / 'bar' / (panel + '.json')).read_text())
        except (OSError, ValueError):
            actions = []
        for row in range(14):
            action = row < len(actions) and actions[row]
            args += ['--set', f'{panel}.row.{row}', 'label.color=' + c('accent' if action else 'foreground')]
    for panel in ('cpu', 'gpu', 'memory'):
        args += ['--set', panel, 'label.color=' + c('muted'),
                 '--set', panel + '.graph', 'graph.color=' + c('accent'), 'graph.fill_color=' + c('accent', '33')]
    for panel in ('volume', 'brightness'):
        args += ['--set', panel + '.slider', 'slider.highlight_color=' + c('accent'),
                 'slider.background.color=' + c('border')]
    args += ['--set', 'clock', 'label.color=' + c('secondary'),
             '--set', 'weather', 'label.color=' + c('secondary'),
             '--set', 'battery', 'label.color=' + c('success')]
    subprocess.run(args, check=True, timeout=5)


if __name__ == '__main__':
    if sys.argv[1:] == ['shell']:
        print(shell(resolve()), end='')
    elif sys.argv[1:] == ['apply']:
        apply()
    else:
        print(json.dumps(resolve()))
