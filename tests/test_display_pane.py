import copy
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'.config/sketchybar/plugins'))
import controls
import display_pane
import wifi_pane


def snapshot():
    return {'sampled': time.time(), 'handoff': False,
            'screens': [{'name': 'Built-in display', 'mode': 'Main display', 'width': 3456, 'height': 2234}],
            'rows': [{'kind': 'toggle', 'text': 'Night Shift', 'page': 'display', 'role': 'AXCheckBox',
                      'identifier': 'display-setting-night-shift', 'selected': False, 'enabled': True},
                     {'kind': 'device', 'text': 'Test display', 'page': 'mirroring', 'role': 'AXCheckBox',
                      'identifier': 'screen-mirroring-device-test', 'selected': False, 'enabled': True},
                     {'kind': 'settings', 'text': 'Display Settings…', 'page': 'mirroring', 'role': 'AXButton',
                      'identifier': 'screen-mirroring-preferences', 'selected': False, 'enabled': True}]}


class DisplayTests(unittest.TestCase):
    def test_fresh_native_discovery_opens_display_without_another_scan(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)/'bar'), \
             patch.object(controls, 'brightness', return_value='54'), patch.object(controls, 'item_anchors', return_value=[]), \
             patch.object(controls, 'native_controls'), patch.object(controls.subprocess, 'Popen'), \
             patch.object(display_pane, 'query') as scan:
            controls.store('display-snapshot.json', snapshot())
            controls.show('brightness', clicked=True)
            document = controls.read('native-panel.json')
            self.assertEqual(document['slider'], 54)
            self.assertEqual(document['request'], str(controls.read('hover.json')[0]))
            self.assertTrue(any(row['action'] for row in document['rows']))
            scan.assert_not_called()

    def test_native_response_rejects_stale_or_forged_controls_and_topology(self):
        good = snapshot()
        self.assertIs(display_pane.validate(good), good)
        bad_values = []
        for stamp in (time.time()-10, time.time()+20, float('nan'), True):
            bad = copy.deepcopy(good); bad['sampled'] = stamp; bad_values.append(bad)
        for key, value in (('identifier', 'wifi-header'), ('page', 'wifi'), ('role', 'AXTextField'),
                           ('selected', 1), ('text', 'Name\nsecret')):
            bad = copy.deepcopy(good); bad['rows'][0][key] = value; bad_values.append(bad)
        for key, value in (('width', -1), ('height', True), ('refresh', float('inf')), ('mode', 'Unknown')):
            bad = copy.deepcopy(good); bad['screens'][0][key] = value; bad_values.append(bad)
        bad = copy.deepcopy(good); bad['rows'].append(bad['rows'][0]); bad_values.append(bad)
        bad = copy.deepcopy(good); bad['rows'].pop(); bad_values.append(bad)
        for bad in bad_values:
            with self.assertRaises(ValueError):
                display_pane.validate(bad)

    def test_only_actual_discovered_devices_are_actionable_and_settings_survives_capacity(self):
        value = snapshot()
        native = value['rows'][1]
        value['rows'][1:2] = [dict(native, text=f'Display {i}', identifier=f'screen-mirroring-device-{i}') for i in range(20)]
        rows = display_pane.panel_rows(value, 45)
        self.assertLessEqual(len(rows), 14)
        self.assertEqual(rows[0][0], 'Display · 45%')
        self.assertEqual(rows[-1][1][1]['kind'], 'settings')
        for _, action in rows:
            if action:
                self.assertIn(action[1], value['rows'])
        value['rows'] = [row for row in value['rows'] if row['kind'] != 'device']
        rows = display_pane.panel_rows(value, 45)
        self.assertIn(('No nearby displays found', None), rows)
        self.assertFalse(any(action and action[1]['kind'] == 'device' for _, action in rows))

    def test_signed_helper_display_protocol_does_not_use_wifi_validator(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp)/'desktop/bar'; state.mkdir(parents=True)
            helper = state.parent/'wifi-pane'; helper.symlink_to('/fixture/Display.app/Contents/MacOS/wifi-pane')
            # The common launcher requires a real file before resolving its bundle.
            with patch.object(Path, 'is_file', return_value=True), patch.object(Path, 'resolve', return_value=Path('/fixture/Display.app/Contents/MacOS/wifi-pane')):
                def reply(args, **kwargs):
                    self.assertIn('--display-snapshot', args)
                    output = Path(args[args.index('--stdout')+1])
                    self.assertEqual(output.stat().st_mode & 0o777, 0o600)
                    output.write_text(json.dumps(snapshot()))
                    return type('Result', (), {'returncode': 0})()
                with patch.object(wifi_pane.subprocess, 'run', side_effect=reply):
                    self.assertEqual(len(display_pane.query(state)['screens']), 1)

    def test_native_handoff_closes_only_current_request(self):
        for changed in (False, True):
            with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
                 patch.object(controls, 'close_panels') as close:
                controls.store('hover.json', [1, 'brightness'])
                value = snapshot(); value['handoff'] = True
                def handoff(*args):
                    if changed:
                        controls.store('hover.json', [2, 'volume'])
                    return value
                with patch.object(display_pane, 'query', side_effect=handoff):
                    result = controls.action(['display-pane', snapshot()['rows'][1]])
                self.assertEqual(close.call_count, 0 if changed else 1)
                self.assertIs(result, None if changed else True)
                if changed:
                    self.assertEqual(controls.read('hover.json'), [2, 'volume'])

    def test_keyboard_brightness_refresh_uses_snapshot_without_native_scan(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)/'bar'), \
             patch.object(controls, 'native_controls'), patch.object(controls, 'brightness', return_value='72'), \
             patch.object(display_pane, 'query') as scan:
            controls.store('hover.json', [1, 'brightness'])
            controls.store('display-snapshot.json', snapshot())
            controls.render_rows('brightness', controls.panel_rows('brightness'))
            (Path(temp)/'status.json').write_text(json.dumps({'updated': time.time(), 'controls': {'visible': True, 'name': 'brightness'}}))
            self.assertTrue(controls.refresh_open('brightness'))
            self.assertEqual(controls.read('native-panel.json')['slider'], 72)
            scan.assert_not_called()
