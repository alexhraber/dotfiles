import copy
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'.config/sketchybar/plugins'))
import controls
import wifi_pane


def option(kind, label, selected=False):
    return {'kind': kind, 'text': label, 'role': 'AXCheckBox', 'identifier': label,
            'selected': selected, 'enabled': True}


def snapshot(rows):
    return {'sampled': time.time(), 'rows': [option('power', 'Wi-Fi', True)] + rows, 'handoff': False}


class WifiPaneTests(unittest.TestCase):
    def test_auxiliary_pane_survives_bar_conceal_but_explicit_cancel_still_closes_it(self):
        for name in ('wifi', 'bluetooth'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp, \
                 patch.object(controls, 'STATE', Path(temp)), patch.object(controls, 'native_controls') as native, \
                 patch.object(controls, 'native_calendar'), patch.object(sys, 'argv', ['controls.py','cancel','all']):
                controls.store('hover.json', [101,name])
                controls.store('active.json', {'name':name, 'backend':'panel-ui', 'request':'101', 'time':time.time()})
                controls.store('panel-ui-status.json', {'name':name, 'request':'101', 'visible':True, 'updated':time.time()})
                with patch.dict(controls.os.environ, SENDER='desktop_concealed'):
                    controls.main()
                native.assert_not_called()
                self.assertEqual(controls.read('hover.json'), [101,name])
                with patch.dict(controls.os.environ, SENDER='explicit'):
                    controls.main()
                native.assert_called_once_with('hide')
                self.assertEqual(controls.read('active.json'), {})

    def test_native_failure_code_survives_nonzero_helper_exit_without_network_names(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp)/'bar'
            target = Path(temp)/'Desktop Panels.app/Contents/MacOS/wifi-pane'
            target.parent.mkdir(parents=True); target.touch()
            (Path(temp)/'wifi-pane').symlink_to(target)
            def run(args, **kwargs):
                Path(args[args.index('--stdout')+1]).write_text(json.dumps({'error':'native_panel_busy'}))
                return SimpleNamespace(returncode=1)
            with patch.object(wifi_pane.subprocess, 'run', side_effect=run), \
                 self.assertRaises(wifi_pane.NativeError) as error:
                wifi_pane.query(state)
            self.assertEqual(error.exception.code, 'native_panel_busy')
            report = json.loads((state/'wifi-diagnostic.json').read_text())
            self.assertEqual((report['stage'], report['code']), ('snapshot', 'native_panel_busy'))
            self.assertEqual((state/'wifi-diagnostic.json').stat().st_mode & 0o777, 0o600)
            self.assertEqual(set(report), {'stage','code','time'})
            wifi_pane.diagnostic(state, 'status', 'access_unavailable',
                                 {'accessibility':False, 'screen_capture':False, 'supported':True})
            self.assertEqual(json.loads((state/'wifi-diagnostic-snapshot.json').read_text()), report)

    def test_unknown_native_error_text_is_never_recorded_as_diagnostics(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp)/'bar'
            target = Path(temp)/'Desktop Panels.app/Contents/MacOS/wifi-pane'
            target.parent.mkdir(parents=True); target.touch()
            (Path(temp)/'wifi-pane').symlink_to(target)
            def run(args, **kwargs):
                Path(args[args.index('--stdout')+1]).write_text(json.dumps({'error':'Private network name'}))
                return SimpleNamespace(returncode=1)
            with patch.object(wifi_pane.subprocess, 'run', side_effect=run), self.assertRaises(wifi_pane.NativeError):
                wifi_pane.query(state)
            self.assertNotIn('Private network name', (state/'wifi-diagnostic.json').read_text())

    def test_owned_fallback_closes_on_busy_and_retries_closing_animation(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_item') as item, patch.object(controls.time, 'sleep'), \
             patch.object(wifi_pane, 'query') as query:
            controls.store('hover.json', [101,'wifi'])
            controls.store('active.json', {'name':'wifi','native_wifi':True})
            def observe(*args):
                if query.call_count == 1:
                    item.assert_not_called()
                    raise wifi_pane.NativeError('native_panel_busy')
                self.assertEqual(controls.read('active.json'), {})
                item.assert_called_once_with('Wi-Fi', ensure='close')
                if query.call_count == 2:
                    raise wifi_pane.NativeError('native_panel_busy')
                return {'snapshot':True}
            query.side_effect = observe
            self.assertEqual(controls.wifi_snapshot([101,'wifi']), {'snapshot':True})
            self.assertEqual(query.call_count, 3)

    def test_missing_access_does_not_close_the_working_native_fallback(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_item') as item, \
             patch.object(wifi_pane, 'query', side_effect=wifi_pane.NativeError('access_unavailable')):
            controls.store('hover.json', [101,'wifi'])
            controls.store('active.json', {'name':'wifi','native_wifi':True})
            with self.assertRaises(wifi_pane.NativeError): controls.wifi_snapshot([101,'wifi'])
            item.assert_not_called()
            self.assertTrue(controls.read('active.json')['native_wifi'])

    def test_unowned_native_panel_is_never_closed_or_retried(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_item') as item, \
             patch.object(wifi_pane, 'query', side_effect=wifi_pane.NativeError('native_panel_busy')) as query:
            controls.store('hover.json', [101,'wifi'])
            with self.assertRaises(wifi_pane.NativeError): controls.wifi_snapshot([101,'wifi'])
            item.assert_not_called()
            self.assertEqual(query.call_count, 1)

    def test_native_order_connected_row_and_three_available_choices(self):
        connected = option('network', 'Current', True)
        data = snapshot([option('section', 'Known Networks'), connected] +
                        [option('network', f'Nearby {i}') for i in range(6)] +
                        [option('disclosure', 'Other Networks'), option('button', 'Wi-Fi Settings…')])
        rows = wifi_pane.panel_rows(data)
        self.assertEqual(rows[0][1], ['wifi-pane', data['rows'][0]])
        self.assertEqual([a[1]['text'] for _, a in rows if a and a[1]['kind'] == 'network'],
                         ['Current', 'Nearby 0', 'Nearby 1', 'Nearby 2'])
        self.assertEqual(rows[-1][0], 'Wi-Fi Settings…')

    def test_status_rows_reserve_space_without_losing_native_settings(self):
        rows = []
        for i in range(4):
            rows += [option('section', f'Group {i}')] + [option('network', f'Network {i}-{j}') for j in range(3)]
        rows += [option('button', 'Wi-Fi Settings…')]
        result = wifi_pane.panel_rows(snapshot(rows), budget=12)
        self.assertLessEqual(len(result), 12)
        self.assertEqual(result[-1][0], 'Wi-Fi Settings…')

    def test_wifi_matches_bluetooth_connected_first_without_duplicate_groups(self):
        connected = option('network', 'Connected network', True)
        native = snapshot([option('section', 'Known Networks'), option('network', 'Saved nearby'),
                           option('disclosure', 'Other Networks'), option('section', 'Nearby'),
                           option('network', 'Nearby 1'), connected, option('network', 'Nearby 2'),
                           option('network', 'Nearby 3'), option('button', 'Wi-Fi Settings…')])
        rows = wifi_pane.panel_rows(native)
        self.assertEqual(rows[1], ('Connected network', ['wifi-pane', connected]))
        self.assertEqual(sum(a[1]['kind'] == 'network' for _, a in rows if a), 4)
        self.assertFalse(any(label in ('Known Networks', 'Nearby') for label, _ in rows))
        self.assertEqual(rows[-2][0], 'Other Networks')
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls'):
            controls.store('hover.json', [102, 'wifi'])
            controls.render_rows('wifi', rows)
            rendered = controls.read('native-panel.json')['rows']
            self.assertTrue(rendered[0]['action'])
            self.assertEqual((rendered[1]['selected'], rendered[1]['detail'], rendered[1]['hint']),
                             (True, 'Connected', 'Disconnect'))
            self.assertEqual((rendered[2]['selected'], rendered[2]['detail'], rendered[2]['hint']),
                             (False, 'Not connected', 'Connect'))

    def test_protocol_rejects_stale_malformed_and_control_character_names(self):
        valid = snapshot([option('network', 'Example')])
        cases = []
        stale = copy.deepcopy(valid); stale['sampled'] -= 10; cases.append(stale)
        no_power = copy.deepcopy(valid); no_power['rows'].pop(0); cases.append(no_power)
        too_long = copy.deepcopy(valid); too_long['rows'][1]['text'] = 'é'*17; cases.append(too_long)
        bad_text = copy.deepcopy(valid); bad_text['rows'][1]['text'] = 'line\ncommand'; cases.append(bad_text)
        bad_bool = copy.deepcopy(valid); bad_bool['rows'][1]['selected'] = 1; cases.append(bad_bool)
        for case in cases:
            with self.subTest(case=case), self.assertRaises(ValueError):
                wifi_pane.validate(case)
        self.assertEqual(wifi_pane.validate(valid), valid)

    def test_netstat_uses_link_counters_without_double_counting_addresses(self):
        data = 'Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll\n' \
               'en0 1500 <Link#14> aa:bb:cc 10 0 12000 20 0 8000 0\n' \
               'en0 1500 192.0.2 192.0.2.5 10 - 12000 20 - 8000 -\n'
        self.assertEqual(wifi_pane.counters(data, 'en0'), (12000, 8000))
        with self.assertRaises(ValueError): wifi_pane.counters(data, 'en1')

    def test_throughput_recovers_from_reset_sleep_and_interface_change(self):
        previous, rate = wifi_pane.rates({}, 'en0', 1000, 2000, 10)
        self.assertIsNone(rate)
        current, rate = wifi_pane.rates(previous, 'en0', 3000, 2400, 12)
        self.assertEqual(rate, (1000, 200))
        self.assertEqual(wifi_pane.speed_label(rate), '↓ 1.0 KB/s   ↑ 200 B/s')
        for device, incoming, outgoing, now in [('en0', 0, 0, 13), ('en1', 4000, 3000, 13), ('en0', 4000, 3000, 30)]:
            self.assertIsNone(wifi_pane.rates(current, device, incoming, outgoing, now)[1])

    def test_bluetooth_header_is_the_only_power_action_and_device_actions_remain(self):
        devices = [{'name': 'Headphones', 'address': 'test-device', 'connected': True}]
        for powered in (True, False):
            with patch.object(controls, 'command', side_effect=lambda *a: ('1' if powered else '0') if '--power' in a else json.dumps(devices)):
                rows = controls.panel_rows('bluetooth')
            self.assertEqual(rows[0], ('Bluetooth · ' + ('On' if powered else 'Off'), ['bluetooth-power', 'off' if powered else 'on']))
            self.assertEqual(sum(bool(a) and a[0] == 'bluetooth-power' for _, a in rows), 1)
            self.assertFalse(any('Turn Bluetooth' in label for label, _ in rows))
            with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
                 patch.object(controls, 'native_controls'), patch.object(controls, 'command') as command:
                controls.store('hover.json', [101, 'bluetooth'])
                controls.render_rows('bluetooth', rows)
                self.assertTrue(controls.read('native-panel.json')['rows'][0]['action'])
                controls.action(controls.read('bluetooth.json')[0])
                command.assert_called_once_with('blueutil', '--power', 'off' if powered else 'on')
            if powered:
                self.assertEqual(rows[1][1], ['bluetooth-device', '--disconnect', 'test-device'])
