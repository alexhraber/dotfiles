"""Project the desktop palette into small, local application configuration files."""
import json
from pathlib import Path
import re


def render(palette, root):
    keys = ('surface', 'popup', 'border', 'foreground', 'muted', 'accent',
            'secondary', 'highlight', 'selection', 'success', 'warning', 'danger')
    if any(not re.fullmatch(r'[0-9a-fA-F]{6}', palette.get(key, '')) for key in keys):
        raise ValueError('Invalid workstation palette')
    p = {key: '#' + palette[key].lower() for key in keys}
    ansi = [p[key] for key in ('popup', 'danger', 'success', 'warning', 'accent',
                              'secondary', 'secondary', 'foreground', 'muted',
                              'danger', 'success', 'warning', 'accent', 'secondary',
                              'secondary', 'foreground')]
    ghostty = '\n'.join([
        '# Generated from the selected dotfiles desktop palette.',
        'background = ' + p['surface'], 'foreground = ' + p['foreground'],
        'cursor-color = ' + p['accent'], 'cursor-text = ' + p['surface'],
        'selection-background = ' + p['selection'],
        'selection-foreground = ' + p['foreground'],
        *[f'palette = {index}={color}' for index, color in enumerate(ansi)], '',
    ])
    tmux = '\n'.join([
        '# Generated from the selected dotfiles desktop palette.',
        f"set -g status-style 'bg={p['popup']},fg={p['foreground']}'",
        f"set -g pane-border-style 'fg={p['border']}'",
        f"set -g pane-active-border-style 'fg={p['accent']}'",
        f"set -g message-style 'bg={p['highlight']},fg={p['foreground']}'",
        f"set -g pane-border-format '#[fg={p['muted']}] #{{pane_index}} · #{{pane_current_command}} '",
        f"setw -g window-status-format '#[fg={p['muted']}] #I #W '",
        f"setw -g window-status-current-format '#[bg={p['selection']},fg={p['accent']},bold] #I #W #[default]'",
        f"set -g status-left '#[bg={p['accent']},fg={p['surface']},bold] ◈ #S #[default]  '",
        f"set -g status-right '#{{?client_prefix,#[bg={p['warning']},fg={p['surface']}] PREFIX #[default] ,}}#[fg={p['muted']}]#h  #[fg={p['secondary']}]%a %d #[fg={p['foreground']}]%H:%M '", '',
    ])
    old = ('#1f2335', '#24283b', '#414868', '#c0caf5', '#565f89', '#7aa2f7',
           '#7dcfff', '#3b4261', '#bb9af7', '#9ece6a', '#e0af68', '#f7768e')
    targets = ('popup', 'surface', 'border', 'foreground', 'muted', 'accent',
               'secondary', 'highlight', 'secondary', 'success', 'warning', 'danger')
    replacements = dict(zip(old, (p[key] for key in targets)))
    starship = (Path(root)/'.config/starship.toml').read_text()
    starship = re.sub('|'.join(map(re.escape, old)), lambda match: replacements[match[0]], starship)
    starship = '# Generated from the selected dotfiles desktop palette.\n' + starship
    colors = ','.join(f'{name}:{p[key]}' for name, key in (
        ('bg+', 'highlight'), ('fg', 'foreground'), ('fg+', 'foreground'),
        ('hl', 'secondary'), ('hl+', 'secondary'), ('border', 'border'),
        ('prompt', 'accent'), ('pointer', 'accent'), ('marker', 'success'),
        ('spinner', 'warning'), ('header', 'muted')))
    shell = ('# Generated palette; sourced after fzf options and before Starship.\n'
             'export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship-theme.toml"\n'
             f'export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --color={colors}"\n')
    return {'ghostty/themes/dotfiles': ghostty, 'tmux/dotfiles-theme.conf': tmux,
            'nvim/dotfiles-theme.json': json.dumps(p, indent=2) + '\n',
            'zsh/theme.zsh': shell, 'starship-theme.toml': starship}
