import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        self.project = self.home / 'project with spaces'
        self.project.mkdir()
        binary = self.home / 'bin'
        binary.mkdir()
        podman = binary / 'podman'
        podman.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['COMMAND_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1] == 'info' and os.environ.get('PODMAN_UNAVAILABLE'):
    sys.exit(125)
''')
        podman.chmod(0o755)
        self.log = self.home / 'commands.jsonl'
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(binary) + os.pathsep + os.environ['PATH'], COMMAND_LOG=str(self.log))

    def run_helper(self, *args, cwd=None):
        return subprocess.run(['zsh', '-c', 'source "$1"; shift; cws "$@"', 'zsh',
                               str(ROOT / '.config/zsh/workspaces.zsh'), *args],
                              cwd=cwd or self.project, env=self.env, text=True, capture_output=True)

    def test_run_preserves_arguments_and_shares_only_project(self):
        result = self.run_helper('registry.example/image@sha256:test', 'printf', '%s', 'value with spaces')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(calls[0], ['info'])
        command = calls[1]
        self.assertEqual(command[-4:], ['registry.example/image@sha256:test', 'printf', '%s', 'value with spaces'])
        self.assertIn('type=bind,source=' + str(self.project.resolve()) + ',destination=/workspace', command)
        self.assertEqual(command.count('--mount'), 1)
        self.assertIn('--cap-drop=all', command)
        self.assertIn('--security-opt=no-new-privileges', command)
        self.assertNotIn('--tty', command)

    def test_unavailable_engine_never_launches_machine(self):
        self.env['PODMAN_UNAVAILABLE'] = '1'
        result = self.run_helper('registry.example/image:1')
        self.assertEqual(result.returncode, 1)
        self.assertIn('headlessly', result.stderr)
        self.assertEqual([json.loads(line) for line in self.log.read_text().splitlines()], [['info']])

    def test_refuses_home_mount_and_requires_explicit_image(self):
        self.assertEqual(self.run_helper('image', cwd=self.home).returncode, 1)
        self.assertEqual(self.run_helper().returncode, 2)
        self.assertFalse(self.log.exists())
