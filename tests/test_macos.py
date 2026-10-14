import contextlib
import copy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import macos_preferences as macos


class MacOSPreferencesTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.settings = self.root / 'settings.json'
        self.settings.write_text(json.dumps({'test.domain': {'repeat': 2, 'extensions': True}}))
        self.values = {'test.domain': {'repeat': 8, 'unrelated': 'preserve'}}
        env = patch.dict(os.environ, {'XDG_STATE_HOME': str(self.root / 'state')})
        env.start()
        self.addCleanup(env.stop)
        reader = patch.object(macos, 'read_domain', side_effect=lambda domain: copy.deepcopy(self.values.get(domain, {})))
        reader.start()
        self.addCleanup(reader.stop)

    def write(self, item, value):
        domain = self.values.setdefault(item['domain'], {})
        if value is None:
            domain.pop(item['key'], None)
        else:
            domain[item['key']] = value['value']

    def apply(self, dry=False):
        with contextlib.redirect_stdout(io.StringIO()), patch.object(macos, 'write', side_effect=self.write):
            return macos.apply(macos.plan(self.settings), dry)

    def test_backups_types_and_restores_absent_keys_without_touching_other_keys(self):
        manifest = self.apply()
        self.assertEqual(manifest.stat().st_mode & 0o777, 0o600)
        self.assertEqual(manifest.parent.stat().st_mode & 0o777, 0o700)
        document = json.loads(manifest.read_text())
        self.assertEqual(document['changes'][0]['original'], {'type': 'int', 'value': 8})
        self.assertIsNone(document['changes'][1]['original'])
        with contextlib.redirect_stdout(io.StringIO()), patch.object(macos, 'write', side_effect=self.write):
            macos.restore(document)
            macos.restore(document)
        self.assertEqual(self.values['test.domain'], {'repeat': 8, 'unrelated': 'preserve'})

    def test_dry_run_does_not_write_or_create_state(self):
        with patch.object(macos, 'write') as write:
            self.assertIsNone(self.apply(True))
            write.assert_not_called()
        self.assertFalse((self.root / 'state').exists())
        self.assertEqual(self.values['test.domain']['repeat'], 8)

    def test_reinstall_is_idempotent(self):
        self.apply()
        before = list((self.root / 'state/dotfiles/backups').iterdir())
        self.assertIsNone(self.apply())
        self.assertEqual(before, list((self.root / 'state/dotfiles/backups').iterdir()))

    def test_later_edit_blocks_whole_restore(self):
        manifest = self.apply()
        self.values['test.domain']['repeat'] = 5
        with patch.object(macos, 'write') as write:
            with self.assertRaisesRegex(ValueError, 'later preference edit'):
                macos.restore(json.loads(manifest.read_text()))
            write.assert_not_called()
        self.assertTrue(self.values['test.domain']['extensions'])

    def test_mid_install_failure_rolls_back_including_failing_key(self):
        changes = macos.plan(self.settings)
        original = copy.deepcopy(self.values)
        calls = 0
        def fail_after_write(item, value):
            nonlocal calls
            calls += 1
            self.write(item, value)
            if calls == 2:
                raise OSError('simulated persistence failure')
        with contextlib.redirect_stdout(io.StringIO()), patch.object(macos, 'write', side_effect=fail_after_write):
            with self.assertRaisesRegex(OSError, 'simulated'):
                macos.apply(changes)
        self.assertEqual(self.values, original)

    def test_boolean_and_integer_are_distinct(self):
        self.values['test.domain']['repeat'] = True
        self.assertEqual(len(macos.plan(self.settings)), 2)

    def test_unsupported_original_type_fails_before_any_write(self):
        self.values['test.domain']['repeat'] = {'custom': 2}
        with patch.object(macos, 'write') as write:
            with self.assertRaisesRegex(ValueError, 'Unsupported preference type'):
                macos.plan(self.settings)
            write.assert_not_called()
