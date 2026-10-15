import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('manage', ROOT / 'scripts/manage.py')
manage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manage)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = patch.dict(os.environ, {'HOME': str(self.home),
                         'XDG_CONFIG_HOME': str(self.home / '.config'),
                         'XDG_STATE_HOME': str(self.home / '.local/state'),
                         'CODEX_HOME': str(self.home / '.codex')})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.args = argparse.Namespace(git_name=None, git_email=None, signing_key=None)

    def apply(self, groups=('terminal', 'git', 'codex'), dry=False):
        with contextlib.redirect_stdout(io.StringIO()):
            return manage.apply(manage.plan(groups, self.args), dry)

    def restore(self, manifest):
        with contextlib.redirect_stdout(io.StringIO()):
            manage.restore(manifest, False)

    def test_default_cli_only_installs_terminal(self):
        result = subprocess.run([str(ROOT / 'install.sh')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / '.zshrc').is_symlink())
        self.assertFalse((self.home / '.gitconfig').exists())
        self.assertFalse((self.home / '.codex').exists())
        self.assertFalse((self.home / 'Library/LaunchAgents').exists())

    def test_dry_run_leaves_home_untouched(self):
        self.assertIsNone(self.apply(dry=True))
        self.assertEqual(list(self.home.iterdir()), [])

    def test_restore_regular_files_symlinks_and_absent_paths(self):
        original = self.home / '.zshrc'
        original.write_text('original shell\n')
        original.chmod(0o640)
        starship = self.home / '.config/starship.toml'
        starship.parent.mkdir()
        starship.symlink_to(self.home / 'missing-starship')
        manifest = self.apply()
        self.assertTrue(original.is_symlink())
        self.assertFalse((self.home / '.codex/config.toml').is_symlink())
        self.restore(manifest)
        self.assertEqual(original.read_text(), 'original shell\n')
        self.assertEqual(original.stat().st_mode & 0o777, 0o640)
        self.assertEqual(os.readlink(starship), str(self.home / 'missing-starship'))
        self.assertFalse((self.home / '.gitconfig').exists())
        self.assertFalse((self.home / '.codex/config.toml').exists())
        self.restore(manifest)  # Repeating restoration is also safe.

    def test_second_install_creates_no_backup(self):
        self.apply()
        before = list((self.home / '.local/state/dotfiles/backups').iterdir())
        self.assertIsNone(self.apply())
        self.assertEqual(before, list((self.home / '.local/state/dotfiles/backups').iterdir()))

    def test_git_identity_and_credentials_are_preserved(self):
        config = self.home / '.gitconfig'
        config.write_text('[user]\n name = Existing User\n email = existing@example.test\n[credential]\n helper = osxkeychain\n')
        self.apply(groups=('git',))
        value = subprocess.check_output(['git', 'config', '--global', 'user.email'], text=True)
        self.assertEqual(value.strip(), 'existing@example.test')
        self.assertIn('osxkeychain', config.read_text())
        self.assertEqual(config.read_text().count('dotfiles.gitconfig'), 1)

    def test_dev_runtime_config_is_backed_up_copied_and_restorable(self):
        config = self.home / '.config/mise/config.toml'
        config.parent.mkdir(parents=True)
        config.write_text('[tools]\nnode = "22"\n')
        manifest = self.apply(groups=('dev',))
        self.assertFalse(config.is_symlink())
        self.assertEqual(config.read_bytes(), (ROOT / '.config/mise/config.toml').read_bytes())
        self.assertIsNone(self.apply(groups=('dev',)))
        self.assertFalse((self.home / '.zshrc').exists())
        self.restore(manifest)
        self.assertEqual(config.read_text(), '[tools]\nnode = "22"\n')

    def test_reverse_preserves_local_shell_settings_and_restores(self):
        local = self.home / '.zshrc.local'
        local.write_text('export MY_SETTING=original')
        manifest = self.apply(groups=('reverse',))
        self.assertIn('export MY_SETTING=original\n', local.read_text())
        self.assertIsNone(self.apply(groups=('reverse',)))
        helper = self.home / '.config/zsh/reverse.zsh'
        self.assertTrue(helper.is_file())
        self.assertFalse(helper.is_symlink())
        self.restore(manifest)
        self.assertEqual(local.read_text(), 'export MY_SETTING=original')
        self.assertFalse(helper.exists())

    def test_codex_auth_and_machine_state_are_untouched(self):
        folder = self.home / '.codex'
        folder.mkdir()
        auth = folder / 'auth.json'
        auth.write_text('do not touch')
        db = folder / 'state.sqlite'
        db.write_bytes(b'local database')
        self.apply(groups=('codex',))
        self.assertEqual(auth.read_text(), 'do not touch')
        self.assertEqual(db.read_bytes(), b'local database')
        self.assertEqual((folder / 'config.toml').stat().st_mode & 0o777, 0o600)

    def test_later_edit_blocks_entire_restore(self):
        manifest = self.apply()
        config = self.home / '.codex/config.toml'
        config.write_text('later user edit')
        with self.assertRaisesRegex(ValueError, 'later edit'):
            self.restore(manifest)
        self.assertTrue((self.home / '.zshrc').is_symlink())
        self.assertEqual(config.read_text(), 'later user edit')

    def test_corrupt_backup_blocks_restore(self):
        config = self.home / '.zshrc'
        config.write_text('original')
        manifest = self.apply(groups=('terminal',))
        items = json.loads(manifest.read_text())['changes']
        saved = next(i['backup'] for i in items if i['target'] == str(config))
        Path(saved).write_text('tampered')
        with self.assertRaisesRegex(ValueError, 'changed backup'):
            self.restore(manifest)
        self.assertTrue(config.is_symlink())

    def test_directory_conflict_changes_nothing(self):
        (self.home / '.zshrc').mkdir()
        with self.assertRaisesRegex(ValueError, 'directory'):
            self.apply()
        self.assertFalse((self.home / '.zprofile').exists())
        self.assertFalse((self.home / '.local').exists())

    def test_failed_install_rolls_back_completed_changes(self):
        original = self.home / '.zprofile'
        original.write_text('original profile')
        real = manage.install_item
        calls = 0
        def fail_once(item):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('simulated install failure')
            return real(item)
        with patch.object(manage, 'install_item', side_effect=fail_once):
            with self.assertRaisesRegex(OSError, 'simulated'):
                self.apply(groups=('terminal',))
        self.assertEqual(original.read_text(), 'original profile')
        self.assertFalse((self.home / '.zshrc').exists())

    def test_remove_only_our_legacy_herdr_link(self):
        target = self.home / '.config/herdr/config.toml'
        target.parent.mkdir(parents=True)
        target.symlink_to(ROOT / '.config/herdr/config.toml')
        manifest = self.apply(groups=('terminal',))
        self.assertFalse(target.is_symlink())
        self.restore(manifest)
        self.assertTrue(target.is_symlink())
        target.unlink()
        target.write_text('independent config')
        self.apply(groups=('terminal',))
        self.assertEqual(target.read_text(), 'independent config')

    def test_nonlogin_shell_loads_tools_and_resourcing_is_idempotent(self):
        if not shutil.which('zsh'):
            self.skipTest('zsh is not installed')
        self.apply(groups=('terminal',))
        command = '''
set -e
(( $path[(Ie)$HOME/.local/bin] ))
(( $+functions[proj] && $+functions[wt] && $+functions[wtnew] ))
(( ! $+aliases[h] && ! $+aliases[mux] && ! $+functions[work] && ! $+aliases[grep] ))
first_hooks="${precmd_functions[*]}"
first_path=$PATH
source ~/.zshrc
[[ ${precmd_functions[*]} == $first_hooks && $PATH == $first_path ]]
'''
        result = subprocess.run(['zsh', '-ic', command], env=dict(os.environ, TERM='xterm-256color', FASTFETCH_DISABLE='1'), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_worktree_helpers_support_spaces(self):
        if not shutil.which('zsh'):
            self.skipTest('zsh is not installed')
        repo = self.home / 'repo with spaces'
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.test', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'initial'], check=True)
        dest = self.home / 'worktree with spaces'
        command = 'source "$1"; cd -- "$2"; wtnew test-branch "$3"; [[ $PWD == "$3" ]]'
        result = subprocess.run(['zsh', '-c', command, 'test', str(ROOT / '.config/zsh/projects.zsh'), str(repo), str(dest)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((dest / '.git').is_file())

    def test_cargo_environment_is_loaded_without_changing_python(self):
        folder = self.home / '.cargo'
        folder.mkdir()
        (folder / 'env').write_text('export PATH="$HOME/.cargo/bin:$PATH"\n')
        self.apply(groups=('terminal',))
        result = subprocess.run(['zsh', '-ic', '(( $path[(Ie)$HOME/.cargo/bin] )) && (( $+functions[mlx] && $+functions[cxlocal] ))'], env=dict(os.environ, TERM='dumb', FASTFETCH_DISABLE='1'), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_local_model_helpers_pass_arguments_without_activation(self):
        folder = self.home / 'mlx environment/bin'
        folder.mkdir(parents=True)
        executable = folder / 'mlx_lm.generate'
        executable.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        executable.chmod(0o755)
        result = subprocess.run(['zsh', '-c', 'source "$1"; mlx --prompt "a prompt with spaces"', 'test', str(ROOT / '.config/zsh/local-models.zsh')], env=dict(os.environ, MLX_ENV=str(folder.parent)), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['--prompt', 'a prompt with spaces'])

    def test_profiles_and_tracked_codex_files_are_allowlisted(self):
        import tomllib
        for path in (ROOT / '.codex').glob('*.toml'):
            data = tomllib.loads(path.read_text())
            self.assertNotIn('profiles', data)
            self.assertNotIn('profile', data)
        repo = self.home / 'ignore-check'
        repo.mkdir()
        shutil.copy2(ROOT / '.gitignore', repo / '.gitignore')
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        result = subprocess.run(['git', 'check-ignore', '--no-index', '.codex/auth.json', '.codex/sessions/example.jsonl', '.codex/config.toml', 'Signing.local.xcconfig', 'local.developerprofile', 'AuthKey.p8'], cwd=repo, text=True, capture_output=True)
        self.assertIn('.codex/auth.json', result.stdout)
        self.assertIn('.codex/sessions/example.jsonl', result.stdout)
        self.assertNotIn('.codex/config.toml', result.stdout)
        for private in ('Signing.local.xcconfig', 'local.developerprofile', 'AuthKey.p8'):
            self.assertIn(private, result.stdout)

    def test_codex_preferences_allow_app_metadata_but_detect_drift(self):
        expected = {'model': 'chosen-model', 'sandbox_workspace_write': {'network_access': True}}
        actual = dict(expected, tui={'screen_reader_detection_done': True})
        self.assertTrue(manage.contains_preferences(actual, expected))
        self.assertFalse(manage.contains_preferences(dict(actual, model='different-model'), expected))
        self.assertFalse(manage.contains_preferences({'model': 'chosen-model'}, expected))


if __name__ == '__main__':
    unittest.main()
