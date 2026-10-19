import json
from pathlib import Path
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import manage
import workstation_theme


class WorkstationThemeTests(unittest.TestCase):
    def test_every_palette_preserves_semantic_colors_across_applications(self):
        palettes = json.loads((ROOT/'.config/sketchybar/themes.json').read_text())['themes']
        for name, palette in palettes.items():
            with self.subTest(name=name):
                rendered = workstation_theme.render(palette, ROOT)
                editor = json.loads(rendered['nvim/dotfiles-theme.json'])
                for key in palette:
                    self.assertEqual(editor[key], '#' + palette[key].lower())
                self.assertIn('background = ' + editor['surface'], rendered['ghostty/themes/dotfiles'])
                self.assertIn('selection-background = ' + editor['selection'], rendered['ghostty/themes/dotfiles'])
                self.assertIn('fg=' + editor['accent'], rendered['tmux/dotfiles-theme.conf'])
                prompt = tomllib.loads(rendered['starship-theme.toml'])
                self.assertEqual(prompt['directory']['style'], 'bold ' + editor['accent'])
                self.assertIn('prompt:' + editor['accent'], rendered['zsh/theme.zsh'])

    def test_unsafe_palette_cannot_write_application_syntax(self):
        palette = json.loads((ROOT/'.config/sketchybar/themes.json').read_text())['themes']['tidal']
        for value in ('abcdef\nkeybind=global:cmd+a=quit', '$(touch /tmp/unsafe)', 'ffffff0', ''):
            with self.subTest(value=value), self.assertRaises(ValueError):
                workstation_theme.render(dict(palette, accent=value), ROOT)

    def test_projection_install_and_rollback_preserve_unrelated_configuration(self):
        palette = json.loads((ROOT/'.config/sketchybar/themes.json').read_text())['themes']['tidal']
        with tempfile.TemporaryDirectory() as temp, patch.dict('os.environ', {'XDG_STATE_HOME':temp+'/state'}):
            config = Path(temp)/'config'
            existing = config/'ghostty/themes/dotfiles'
            existing.parent.mkdir(parents=True)
            existing.write_text('old local theme\n')
            unrelated = config/'ghostty/config'
            unrelated.write_text('font-size = 19\n')
            ops = [manage.operation(config/rel, content=value)
                   for rel, value in workstation_theme.render(palette, ROOT).items()]
            manifest = manage.apply(ops)
            self.assertEqual(unrelated.read_text(), 'font-size = 19\n')
            self.assertEqual(existing.stat().st_mode & 0o777, 0o600)
            manage.restore(manifest, False)
            self.assertEqual(existing.read_text(), 'old local theme\n')
            self.assertFalse((config/'nvim/dotfiles-theme.json').exists())
            self.assertEqual(unrelated.read_text(), 'font-size = 19\n')
