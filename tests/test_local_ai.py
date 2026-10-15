import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import local_ai


class LocalAiTests(unittest.TestCase):
    def test_failed_activation_preserves_original_directory_and_recovery_state(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            stable=root/'mlx'
            stable.mkdir()
            (stable/'original').write_text('working')
            manifest=root/'manifest.json'
            with patch.object(local_ai,'link',side_effect=OSError('simulated activation failure')):
                with self.assertRaisesRegex(OSError,'activation failure'):
                    local_ai.activate(stable,root/'new',manifest)
            self.assertEqual((stable/'original').read_text(),'working')
            self.assertFalse(json.loads(manifest.read_text())['active'])

    def test_original_directory_is_retained_and_restored(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            stable=root/'mlx'
            stable.mkdir()
            (stable/'original').write_text('existing environment')
            prepared=root/'prepared'
            prepared.mkdir()
            manifest=root/'manifest.json'
            local_ai.activate(stable,prepared,manifest)
            self.assertEqual(stable.resolve(),prepared.resolve())
            original=json.loads(manifest.read_text())
            self.assertEqual((Path(original['backup'])/'original').read_text(),'existing environment')
            local_ai.restore(manifest)
            self.assertFalse(stable.is_symlink())
            self.assertEqual((stable/'original').read_text(),'existing environment')
            local_ai.restore(manifest)

    def test_reapply_retains_first_symlink_baseline(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            stable=root/'mlx'
            stable.symlink_to('old-environment')
            manifest=root/'manifest.json'
            local_ai.activate(stable,root/'one',manifest)
            local_ai.activate(stable,root/'two',manifest)
            local_ai.restore(manifest)
            self.assertEqual(os.readlink(stable),'old-environment')

    def test_later_pointer_edit_blocks_restore(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            stable=root/'mlx'
            manifest=root/'manifest.json'
            local_ai.activate(stable,root/'prepared',manifest)
            stable.unlink()
            stable.symlink_to('manual-choice')
            with self.assertRaisesRegex(ValueError,'edited later'):
                local_ai.restore(manifest)
            self.assertEqual(os.readlink(stable),'manual-choice')
