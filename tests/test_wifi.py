import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.config/sketchybar/plugins'))
import wifi
import controls


def snapshot(**values):
    result = {'authorization':'authorized','services':True,'sampled':time.time(),
              'interface':'en0','ssid':'Current','networks':[]}
    result.update(values)
    return result


def network(name, known=False, rssi=-40):
    return {'ssid':name,'known':known,'secure':True,'rssi':rssi}


class WifiTests(unittest.TestCase):
    def test_scan_availability_is_intersected_with_recent_use_not_invented_from_history(self):
        scan=snapshot(networks=[network('Current'),network('Cafe',True,-70),
            network('Office',True,-60),network('New',False,-20),network('Other',False,-30)])
        rows=wifi.choices(scan,{'Unavailable':999,'Cafe':700,'Office':900},now=1000)
        self.assertEqual([row['ssid'] for row in rows],['Office','Cafe','New'])
        self.assertNotIn('Unavailable',[row['ssid'] for row in rows])

    def test_invalid_history_cannot_fake_recency_and_duplicates_collapse(self):
        scan=snapshot(networks=[network('Cafe',True,-60),network('Cafe',True,-40),network('Office',True,-50)])
        for history in ({'Office':float('inf')},{'Office':True},{'Office':1001},None):
            self.assertEqual([row['ssid'] for row in wifi.choices(scan,history,now=1000)],['Cafe','Office'])

    def test_scan_is_invalidated_by_time_connection_interface_and_link_events(self):
        status=snapshot(); scan=snapshot(sampled=990)
        for change in ({'sampled':980},{'ssid':'Old'},{'interface':'en1'},
                       {'authorization':'denied'},{'services':False},{'error':'scan failed'}):
            with self.subTest(change=change):
                self.assertFalse(wifi.current_scan(dict(scan,**change),status,now=995))
        self.assertTrue(wifi.current_scan(scan,status,now=995))
        self.assertFalse(wifi.current_scan(scan,status,invalidated=991,now=995))

    def test_permission_off_strips_network_names_without_scanning_or_requesting(self):
        result=wifi.validate(snapshot(authorization='denied',networks=[network('Must disappear')]))
        self.assertEqual((result['ssid'],result['networks']),('',[]))

    def test_malformed_network_data_is_rejected_and_literal_names_survive(self):
        name=' Cafe; $(literal) '
        self.assertEqual(wifi.validate(snapshot(networks=[network(name)]))['networks'][0]['ssid'],name)
        for row in (network('x'*33),network('bad\nname'),network('Okay',rssi=True),
                    dict(network('Okay'),known='yes')):
            with self.assertRaises(ValueError):wifi.validate(snapshot(networks=[row]))
        with self.assertRaises(ValueError):wifi.validate(snapshot(sampled=time.time()-20))

    def test_query_is_background_and_permission_request_requires_explicit_mode(self):
        for request in (False,True):
            with self.subTest(request=request), tempfile.TemporaryDirectory() as temp:
                root=Path(temp); state=root/'bar'; helper=root/'App.app/Contents/MacOS/wifi-access'
                helper.parent.mkdir(parents=True); helper.write_text('fixture'); (root/'wifi-access').symlink_to(helper)
                def run(args,**kwargs):
                    output=Path(args[args.index('--stdout')+1]); output.write_text(json.dumps(snapshot()))
                    self.assertEqual(output.stat().st_mode&0o777,0o600)
                    self.assertEqual(args[-1],'--request-access' if request else '--scan')
                    self.assertEqual('-g' in args,not request)
                with patch.object(wifi.subprocess,'run',side_effect=run):
                    wifi.query(state,scan=True,request_access=request)
                self.assertFalse(list(state.glob('wifi-result-*')))

    def test_query_timeout_removes_private_result_file(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); state=root/'bar'; helper=root/'App.app/Contents/MacOS/wifi-access'
            helper.parent.mkdir(parents=True); helper.write_text('fixture'); (root/'wifi-access').symlink_to(helper)
            with patch.object(wifi.subprocess,'run',side_effect=subprocess.TimeoutExpired('open',12)):
                with self.assertRaises(subprocess.TimeoutExpired):wifi.query(state)
            self.assertFalse(list(state.glob('wifi-result-*')))

    def test_hidden_wifi_watch_does_not_start_any_scan(self):
        with patch.object(controls,'visible_control',return_value=False),patch.object(wifi,'query') as query:
            controls.wifi_watch('1')
            query.assert_not_called()

    def test_scan_result_is_discarded_if_the_pane_is_closed_during_the_scan(self):
        with tempfile.TemporaryDirectory() as temp,patch.object(controls,'STATE',Path(temp)), \
             patch.object(controls,'visible_control',side_effect=[True,True,False]), \
             patch.object(wifi,'query',return_value=snapshot(networks=[network('Private')])), \
             patch.object(controls,'refresh_open') as refresh:
            controls.wifi_watch('1')
            self.assertIsNone(controls.read('wifi-scan.json'))
            refresh.assert_not_called()

    def test_failed_refresh_removes_stale_network_actions_instead_of_retaining_them(self):
        with tempfile.TemporaryDirectory() as temp,patch.object(controls,'STATE',Path(temp)/'bar'), \
             patch.object(controls,'panel_rows',side_effect=ValueError('unavailable')), \
             patch.object(controls,'visible_control',return_value=True),patch.object(controls,'native_controls'):
            controls.store('hover.json',[1,'wifi'])
            controls.store('wifi.json',[['wifi-network','Stale']])
            self.assertTrue(controls.refresh_open('wifi'))
            self.assertNotIn(['wifi-network','Stale'],controls.read('wifi.json'))
            self.assertIn('Could not refresh',controls.read('native-panel.json')['rows'][1]['text'])

    def test_denying_permission_does_not_open_settings_or_repeat_the_request(self):
        with patch.object(wifi,'query',side_effect=[snapshot(authorization='notDetermined'),
                snapshot(authorization='denied')]) as query,patch.object(controls,'command') as command:
            controls.action(['wifi-access'])
            query.assert_any_call(controls.STATE,request_access=True)
            command.assert_not_called()

    def test_changed_availability_rejects_a_stale_network_action(self):
        with tempfile.TemporaryDirectory() as temp,patch.object(controls,'STATE',Path(temp)), \
             patch.object(wifi,'query',return_value=snapshot()),patch.object(controls,'command') as command:
            controls.store('wifi-scan.json',snapshot(networks=[network('Other')],sampled=time.time()-30))
            with self.assertRaises(ValueError):controls.action(['wifi-network','Other'])
            command.assert_not_called()

    def test_join_passes_literal_ssid_without_password_and_keeps_pending_state(self):
        name='Cafe; $(literal)'
        with tempfile.TemporaryDirectory() as temp,patch.object(controls,'STATE',Path(temp)), \
             patch.object(wifi,'query',return_value=snapshot()),patch.object(controls,'refresh_open'), \
             patch.object(controls,'wifi_device',return_value='en0'),patch.object(controls,'command',return_value='') as command:
            controls.store('wifi-scan.json',snapshot(networks=[network(name,True)]))
            controls.action(['wifi-network',name])
            command.assert_called_once_with('/usr/sbin/networksetup','-setairportnetwork','en0',name,timeout=20)
            self.assertEqual(controls.read('wifi-pending.json')['ssid'],name)

    def test_exit_zero_join_error_clears_connecting_state(self):
        with tempfile.TemporaryDirectory() as temp,patch.object(controls,'STATE',Path(temp)), \
             patch.object(wifi,'query',return_value=snapshot()),patch.object(controls,'refresh_open'), \
             patch.object(controls,'wifi_device',return_value='en0'),patch.object(controls,'command',return_value='Could not find network'):
            controls.store('wifi-scan.json',snapshot(networks=[network('Other',True)]))
            with self.assertRaises(ValueError):controls.action(['wifi-network','Other'])
            self.assertEqual(controls.read('wifi-pending.json'),{})

    def test_new_secured_network_uses_system_password_ui_without_reading_credentials(self):
        name='Cafe; $(literal)'
        with tempfile.TemporaryDirectory() as temp,patch.object(controls,'STATE',Path(temp)), \
             patch.object(wifi,'query',return_value=snapshot()),patch.object(controls,'native_wifi_connect') as native, \
             patch.object(controls,'command') as command:
            controls.store('wifi-scan.json',snapshot(networks=[network(name)]))
            controls.action(['wifi-native-network',name])
            native.assert_called_once_with(name)
            command.assert_not_called()
