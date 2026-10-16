"""Single owner for portable checks, shared by CLI, CI and repository proof."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def main():
    subprocess.run(['shellcheck', 'install.sh', 'scripts/dotfiles', 'scripts/check',
                    'scripts/setup-xcode', '.config/sketchybar/sketchybarrc',
                    '.config/sketchybar/plugins/status.sh', '.config/borders/bordersrc'], cwd=ROOT, check=True)
    for source in ('.zshrc', '.zprofile', '.config/zsh/env.zsh',
                   '.config/zsh/projects.zsh', '.config/zsh/local-models.zsh',
                   '.config/zsh/workspaces.zsh', '.config/zsh/reverse.zsh'):
        subprocess.run(['zsh', '-n', source], cwd=ROOT, check=True)
    if sys.platform == 'darwin':
        with tempfile.TemporaryDirectory(prefix='dotfiles-native-check-') as temp:
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                            '-mmacosx-version-min=14.0', '-framework', 'AppKit', '-framework', 'QuartzCore', '-framework', 'EventKit', '-framework', 'ApplicationServices',
                            'scripts/desktop-edge.m', 'scripts/calendar-panel.m', 'scripts/control-panel.m', 'scripts/app-menu.m',
                            '-o', str(Path(temp) / 'desktop-edge')], cwd=ROOT, check=True)
            subprocess.run([str(Path(temp) / 'desktop-edge'), '--self-test'], check=True)
            subprocess.run(['xcrun', 'swiftc', '-typecheck', 'scripts/set-wallpaper.swift'],
                           cwd=ROOT, check=True)
    suite = unittest.defaultTestLoader.discover(str(ROOT / 'tests'))
    return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1


if __name__ == '__main__':
    raise SystemExit(main())
