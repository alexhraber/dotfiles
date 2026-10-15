import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / '.config/sketchybar/plugins'))
import desktop
import controls
import appearance

spec = importlib.util.spec_from_file_location('metrics', ROOT / '.config/sketchybar/plugins/metrics.py')
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class DesktopTests(unittest.TestCase):
    def test_theme_text_and_controls_have_readable_contrast(self):
        def luminance(hex_color):
            values = [int(hex_color[i:i+2],16)/255 for i in (0,2,4)]
            values = [v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in values]
            return sum(a*b for a,b in zip(values,(0.2126,0.7152,0.0722)))
        for theme in ('tidal','ember','iris'):
            palette = appearance.resolve(theme,'ribbon')
            for foreground in ('foreground','muted','accent','secondary','warning','danger'):
                for background in ('surface','popup'):
                    ratio = (luminance(palette[foreground])+0.05)/(luminance(palette[background])+0.05)
                    self.assertGreaterEqual(ratio,4.5,(theme,foreground,background,ratio))

    def test_invalid_theme_cannot_become_shell_configuration(self):
        with self.assertRaises(ValueError):
            appearance.resolve('$(touch /tmp/unwanted)','ribbon')
        with self.assertRaises(ValueError):
            appearance.resolve('tidal','invalid')

    def test_live_theme_switch_preserves_items_and_uses_one_ipc_call(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(appearance,'STATE',Path(temp)), \
             patch.object(appearance.subprocess,'run') as run:
            appearance.save(appearance.resolve('ember','islands'))
            appearance.apply()
        run.assert_called_once()
        argv = run.call_args.args[0]
        for group, drawing in (('ribbon','off'),('hardware','on'),('notifications','on')):
            at = argv.index(group)
            self.assertEqual(argv[at+1],'background.drawing='+drawing)
            self.assertEqual(argv[at+2], 'drawing='+drawing)
        for boundary in ('hardware', 'session', 'notifications'):
            at = argv.index('gap_' + boundary)
            self.assertEqual(argv[at+1], 'drawing=on')
        self.assertNotIn('--reload',argv)
        self.assertNotIn('--remove',argv)

    def test_cached_hover_renders_without_waiting_for_device_commands(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'bar') as bar, patch.object(controls.time, 'sleep'), \
             patch.object(controls, 'panel_rows', side_effect=AssertionError('slow device query')):
            controls.store('volume.cache.json', {'time': time.time(), 'rows': [['Sound · 50%', None]]})
            controls.show('volume')
            self.assertTrue(any('popup.drawing=on' in call.args for call in bar.call_args_list))

    def test_shorter_popup_clears_previous_actions_and_rows(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'bar') as bar:
            controls.render_rows('bluetooth', [('Bluetooth', None)])
            args = bar.call_args.args
            at = args.index('bluetooth.row.5')
            row = args[at:args.index('--set', at)]
            self.assertIn('drawing=off', row)
            self.assertIn('click_script=', row)
            self.assertIn('script=', row)

    def test_leaving_before_hover_dwell_cancels_pending_popup(self):
        def during_dwell(seconds):
            if seconds == 0.12:
                controls.leave('cpu')
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'bar') as bar, \
             patch.object(controls.time, 'sleep', side_effect=during_dwell), \
             patch.object(controls, 'panel_rows', side_effect=AssertionError('cancelled hover fetched data')):
            controls.show('cpu')
            self.assertFalse(any('popup.drawing=on' in call.args for call in bar.call_args_list))

    def test_repeated_hover_does_not_close_and_reopen_current_panel(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'bar') as bar, patch.object(controls.time, 'sleep') as sleep:
            controls.render_rows('volume', [('Sound', None)])
            controls.store('volume.cache.json', {'time': time.time(), 'rows': [['Sound', None]]})
            bar.reset_mock()
            controls.show('volume')
            sleep.assert_not_called()
            bar.assert_called_once()
            self.assertNotIn('popup.drawing=off', bar.call_args.args)

    def test_panel_switch_commits_close_and_open_in_one_ipc(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'bar') as bar:
            controls.render_rows('cpu', [('CPU', None)])
            bar.reset_mock()
            controls.render_rows('gpu', [('GPU', None)])
            bar.assert_called_once()
            args = bar.call_args.args
            self.assertEqual(args[:4], ('--set', 'cpu', 'popup.drawing=off', 'background.drawing=off'))
            self.assertIn('popup.drawing=on', args)
            self.assertEqual(controls.read('active.json')['name'], 'gpu')

    def test_anchor_to_information_row_keeps_popup_without_action_highlight(self):
        def cross_into_popup(seconds):
            if seconds == 0.24:
                controls.keep('cpu.row.0')
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'bar') as bar, \
             patch.object(controls.time, 'sleep', side_effect=cross_into_popup):
            controls.render_rows('cpu', [('CPU', None)])
            controls.store('hover.json', [1, 'cpu'])
            bar.reset_mock()
            controls.leave('cpu')
            self.assertEqual(controls.read('active.json')['name'], 'cpu')
            self.assertFalse(any('popup.drawing=off' in call.args for call in bar.call_args_list))
            self.assertIn('background.drawing=off', bar.call_args.args)
            # Information rows need events too, so crossing them cancels close.
            controls.render_rows('cpu', [('CPU', None)])
            self.assertTrue(any(arg.startswith('script=') and arg != 'script=' for arg in bar.call_args.args))

    def test_old_row_exit_cannot_cancel_new_panel_hover(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'bar'), patch.object(controls.time, 'sleep') as sleep:
            controls.store('hover.json', [2, 'gpu'])
            controls.leave('cpu.row.0')
            self.assertEqual(controls.read('hover.json'), [2, 'gpu'])
            sleep.assert_not_called()

    def test_slow_refresh_cannot_replace_newer_hover_panel(self):
        def newer_hover(name):
            controls.store('hover.json', [2, 'gpu'])
            controls.render_rows('gpu', [('GPU', None)])
            return [('CPU slow response', None)]
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'bar') as bar, patch.object(controls.time, 'sleep'), \
             patch.object(controls, 'fresh_rows', side_effect=newer_hover):
            controls.show('cpu')
            self.assertEqual(controls.read('active.json')['name'], 'gpu')
            self.assertNotIn('label=CPU slow response', bar.call_args.args)

    def test_agent_reapply_keeps_stable_launch_path_and_restarts_new_build(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            agent = root / 'agent.plist'
            tools = {'desktop-edge': str(root / 'build-one')}
            with patch.object(desktop, 'agent_path', return_value=agent), \
                 patch.object(desktop.shutil, 'which', return_value='/opt/homebrew/bin/sketchybar'), \
                 patch.object(desktop, 'agent_loaded', return_value=False), \
                 patch.object(desktop, 'unload'), patch.object(desktop, 'run') as run:
                desktop.write_agent(root, tools)
            original = agent.read_bytes()
            self.assertEqual(os.readlink(root / 'desktop-edge'), tools['desktop-edge'])
            with patch.object(desktop, 'agent_path', return_value=agent), \
                 patch.object(desktop.shutil, 'which', return_value='/opt/homebrew/bin/sketchybar'), \
                 patch.object(desktop, 'agent_loaded', return_value=True), \
                 patch.object(desktop, 'unload') as unload, patch.object(desktop, 'run') as run:
                desktop.write_agent(root, {'desktop-edge': str(root / 'build-two')})
            self.assertEqual(agent.read_bytes(), original)
            unload.assert_not_called()
            run.assert_called_once_with('launchctl', 'kickstart', '-k', f'gui/{os.getuid()}/{desktop.LABEL}')

    def test_device_actions_are_argv_even_with_hostile_names(self):
        name = 'Speaker \"; $(touch /tmp/should-not-exist)'
        with patch.object(controls, 'command') as command:
            controls.action(['output', name])
        command.assert_called_once_with('SwitchAudioSource', '-t', 'output', '-s', name)

    def test_volume_is_clamped_before_invoking_applescript(self):
        with patch.object(controls, 'command') as command:
            controls.action(['volume', '150'])
        command.assert_called_once_with('osascript', '-e', 'set volume output volume 100')

    def test_brightness_is_clamped_before_native_control(self):
        with patch.object(controls, 'brightness') as brightness, patch.object(controls, 'fresh_rows'):
            controls.action(['brightness', '-20'])
        brightness.assert_called_once_with('0')

    def test_low_battery_alert_only_while_discharging(self):
        self.assertEqual(controls.alerts({}, '10%; discharging; 0:30 remaining'), ['Battery low: 10%'])
        self.assertEqual(controls.alerts({}, '10%; charging; 1:00 remaining'), [])

    def test_restore_guards_all_preferences_before_writing_any(self):
        document = {'preferences': [
            dict(desktop.PREFERENCES[0], original=None),
            dict(desktop.PREFERENCES[2], original=None),
        ]}
        with patch.object(desktop.macos_preferences, 'current', side_effect=[
                desktop.PREFERENCES[0]['installed'], {'type': 'float', 'value': 5.0}]):
            with self.assertRaisesRegex(ValueError, 'later preference edit'):
                desktop.validate_preferences(document)

    def test_undo_restores_only_services_started_by_profile(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            agent = root / 'agent.plist'
            agent.write_text('owned agent')
            document = {'active': True,
                        'tools': {'desktop-edge': 'edge', 'wallpaper': 'wallpaper'},
                        'services': {'sketchybar': False, 'borders': True},
                        'preferences': [dict(desktop.PREFERENCES[0], original=None)]}
            with patch.object(desktop, 'unload') as unload, patch.object(desktop, 'run') as run, \
                 patch.object(desktop, 'agent_path', return_value=agent), \
                 patch.object(desktop.macos_preferences, 'current', return_value=desktop.PREFERENCES[0]['installed']), \
                 patch.object(desktop.macos_preferences, 'write') as write:
                desktop.restore_runtime(root, document)
            unload.assert_called_once()
            self.assertEqual(run.call_args_list[0].args, ('edge', '--restore'))
            write.assert_called_once_with(document['preferences'][0], None)
            stops = [call.args for call in run.call_args_list if call.args[:3] == ('brew', 'services', 'stop')]
            self.assertEqual(stops, [('brew', 'services', 'stop', 'felixkratz/formulae/sketchybar')])
            self.assertFalse(agent.exists())
            self.assertFalse(json.loads((root / 'manifest.json').read_text())['active'])
            self.assertEqual((root / 'manifest.json').stat().st_mode & 0o777, 0o600)

    def test_menu_recovers_even_when_later_preference_edit_blocks_undo(self):
        with tempfile.TemporaryDirectory() as temp:
            document = {'tools': {'desktop-edge': 'edge'}, 'preferences': []}
            with patch.object(desktop, 'unload'), patch.object(desktop, 'run') as run, \
                 patch.object(desktop, 'validate_preferences', side_effect=ValueError('later edit')):
                with self.assertRaisesRegex(ValueError, 'later edit'):
                    desktop.restore_runtime(Path(temp), document)
            run.assert_called_once_with('edge', '--restore')

    def test_telemetry_handles_heat_and_swap_without_hiding_them(self):
        sample = {'cpu_scaled_ratio': 0.98, 'gpu_scaled_ratio': 0.25,
                  'temp': {'cpu_temp_avg': 96, 'gpu_temp_avg': 64},
                  'memory': {'ram_usage': 40 * 2**30, 'ram_total': 64 * 2**30, 'swap_usage': 2**29}}
        result = metrics.labels(sample)
        self.assertEqual(result['cpu'], ('98%', '0xffff6b81'))
        self.assertEqual(result['gpu'][0], '25%')
        self.assertEqual(result['memory'], ('40G', '0xffffd166'))

    def test_zero_swap_is_quiet_and_hardware_hover_keeps_fahrenheit(self):
        sample = {'cpu_scaled_ratio': 0, 'gpu_scaled_ratio': 0,
                  'temp': {'cpu_temp_avg': 45, 'gpu_temp_avg': 40},
                  'memory': {'ram_usage': 10 * 2**30, 'ram_total': 64 * 2**30, 'swap_usage': 0}}
        result = metrics.labels(sample)
        self.assertEqual(result['memory'][0], '10G')
        self.assertEqual(result['cpu'][0], '0%')
        with patch.object(controls, 'sample', return_value=sample):
            self.assertIn(('Temperature · 113.0°F', None), controls.panel_rows('cpu'))
