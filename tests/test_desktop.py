import importlib.util
from datetime import datetime
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / '.config/sketchybar/plugins'))
import desktop
import controls
import appearance
import wifi

spec = importlib.util.spec_from_file_location('metrics', ROOT / '.config/sketchybar/plugins/metrics.py')
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class DesktopTests(unittest.TestCase):
    def setUp(self):
        query = patch.object(wifi, 'query', return_value={'authorization':'notDetermined',
            'services':True,'ssid':'','networks':[]})
        self.wifi_query = query.start(); self.addCleanup(query.stop)
        worker = patch.object(controls, 'start_wifi_watch')
        worker.start(); self.addCleanup(worker.stop)

    def test_control_access_requires_current_healthy_fresh_helper(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(desktop,'agent_pid',return_value=17):
            root=Path(temp)
            for case in ('ready','old-pid','stale','unhealthy','not-approved','missing'):
                status={'healthy':True,'pid':17,'updated':time.time(),'app_menus':{'accessibility':1}}
                if case=='old-pid':status['pid']=16
                if case=='stale':status['updated']-=10
                if case=='unhealthy':status['healthy']=False
                if case=='not-approved':status['app_menus']['accessibility']=0
                if case=='missing':status.pop('app_menus')
                (root/'status.json').write_text(json.dumps(status))
                self.assertEqual(desktop.control_access_ready(root),case=='ready',case)

    def test_permission_approval_requests_actual_helper_and_refreshes_owned_runtime(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(desktop,'state_dir',return_value=Path(temp)), \
             patch.object(desktop.os,'uname',return_value=SimpleNamespace(sysname='Darwin')), \
             patch.object(desktop,'agent_loaded',return_value=True), patch.object(desktop,'control_access_ready',return_value=True), \
             patch.object(desktop,'wait_healthy') as healthy, patch.object(desktop,'run') as run:
            self.assertEqual(desktop.main('permissions'),0)
            self.assertEqual(run.call_args_list,[unittest.mock.call(Path(temp)/'desktop-edge','--app-menu','access'),
                unittest.mock.call('launchctl','kickstart','-k',f'gui/{os.getuid()}/{desktop.LABEL}')])
            healthy.assert_called_once_with(Path(temp))

    def test_unapproved_permission_never_restarts_or_grants_access(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(desktop,'state_dir',return_value=Path(temp)), \
             patch.object(desktop.os,'uname',return_value=SimpleNamespace(sysname='Darwin')), \
             patch.object(desktop,'agent_loaded',return_value=True), patch.object(desktop,'control_access_ready',return_value=False), \
             patch.object(desktop.time,'monotonic',side_effect=[10,11,50]), patch.object(desktop.time,'sleep'), \
             patch.object(desktop,'wait_healthy') as healthy, patch.object(desktop,'run') as run:
            self.assertEqual(desktop.main('permissions'),1)
            self.assertEqual(run.call_args_list,[unittest.mock.call(Path(temp)/'desktop-edge','--app-menu','access'),
                unittest.mock.call('open','x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility')])
            healthy.assert_not_called()

    def test_wifi_lists_no_saved_profiles_and_uses_native_availability_picker(self):
        queries=[]
        def command(*args,**kwargs):
            queries.append(args)
            if '-getairportpower' in args: return 'Wi-Fi Power (en0): On'
            if args[:1]==('/sbin/ifconfig',): return 'status: active\n'
            if '-getairportnetwork' in args: return 'You are not associated with an AirPort network.\n'
            if args[:2]==('ipconfig','getifaddr'): return '192.0.2.1'
            raise AssertionError('Unexpected network query: '+repr(args))
        with patch.object(controls,'wifi_device',return_value='en0'), patch.object(controls,'command',side_effect=command):
            rows=controls.panel_rows('wifi')
        self.assertIn(('Available networks & connection…',['native','Wi-Fi']),rows)
        self.assertFalse(any(action and action[0]=='wifi-network' for _,action in rows))
        self.assertFalse(any('saved' in title.lower() for title,_ in rows))
        self.wifi_query.assert_called_once_with(controls.STATE)
        self.assertFalse(any('-listpreferredwirelessnetworks' in call for call in queries))

    def test_wifi_connection_label_preserves_literal_ssid_and_redacted_names_are_omitted(self):
        with patch.object(controls,'command',return_value='Current Wi-Fi Network:  Cafe \n'):
            self.assertEqual(controls.current_wifi('en0'),' Cafe ')
        with patch.object(controls,'command',return_value='You are not associated with an AirPort network.\n'):
            self.assertEqual(controls.current_wifi('en0'),'')

    def test_wifi_never_renders_the_old_saved_network_cache(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)), \
             patch.object(controls,'native_controls'), patch.object(controls,'fresh_rows',return_value=[('Wi-Fi',None),('Available networks & connection…',['native','Wi-Fi'])]), \
             patch.object(controls.time,'sleep'), patch.object(controls,'render_rows',return_value=True) as render:
            controls.store('wifi.cache.json',{'time':time.time(),'rows':[['Old saved profile',['wifi-network','Fake old SSID']]]})
            controls.show('wifi')
            self.assertFalse(any('Old saved profile' in str(call) for call in render.call_args_list))

    def test_wifi_connection_summary_follows_link_and_address_without_claiming_internet(self):
        for linked,address,expected in ((True,'192.0.2.2','Connected'),(True,'169.254.1.2','Limited'),(True,None,'Link active'),(False,None,'Not connected')):
            with self.subTest(state=expected):
                def command(*args,**kwargs):
                    if '-getairportpower' in args:return 'Wi-Fi Power (en0): On'
                    if args[0]=='/sbin/ifconfig':return 'status: '+('active' if linked else 'inactive')+'\n'
                    if args[0]=='ipconfig':
                        if address is None:raise subprocess.CalledProcessError(1,args)
                        return address
                    raise AssertionError(args)
                with patch.object(controls,'wifi_device',return_value='en0'), patch.object(controls,'current_wifi',return_value=''), patch.object(controls,'command',side_effect=command):
                    rows=controls.panel_rows('wifi')
                self.assertEqual(rows[0],('Wi-Fi · '+expected,None))
                self.assertIn(('Available networks & connection…',['native','Wi-Fi']),rows)
                self.assertFalse(any('internet' in title.lower() for title,_ in rows))

    def test_wifi_off_does_not_query_current_network_or_link(self):
        with patch.object(controls,'wifi_device',return_value='en0'), patch.object(controls,'command',return_value='Wi-Fi Power (en0): Off') as command:
            rows=controls.panel_rows('wifi')
        command.assert_called_once_with('networksetup','-getairportpower','en0')
        self.assertEqual(rows[0],('Wi-Fi · Off',None))
        self.assertIn(('Turn Wi-Fi on',['wifi','en0','on']),rows)

    def test_bluetooth_actions_say_connect_or_disconnect(self):
        def command(*args,**kwargs):
            return '1' if '--power' in args else json.dumps([{'name':'Headphones','address':'fake-one','connected':True},{'name':'Keyboard','address':'fake-two','connected':False}])
        with patch.object(controls,'command',side_effect=command):rows=controls.panel_rows('bluetooth')
        self.assertIn(('Disconnect Headphones',['bluetooth-device','--disconnect','fake-one']),rows)
        self.assertIn(('Connect Keyboard',['bluetooth-device','--connect','fake-two']),rows)

    def test_connected_bluetooth_devices_precede_disconnected_devices(self):
        devices=[{'name':'Keyboard','address':'fake-keyboard','connected':False},
                 {'name':'Headphones','address':'fake-headphones','connected':True}]
        with patch.object(controls,'command',side_effect=lambda *args,**kwargs: '1' if '--power' in args else json.dumps(devices)):
            rows=controls.panel_rows('bluetooth')
        self.assertLess(next(i for i,(_,a) in enumerate(rows) if a and 'fake-headphones' in a),
                        next(i for i,(_,a) in enumerate(rows) if a and 'fake-keyboard' in a))

    def test_output_and_bluetooth_state_keeps_the_literal_device_action(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)), patch.object(controls,'native_controls'):
            controls.render_rows('volume',[('Sound · 50%',None),('Output devices',None),('● My "Speaker"',['output','My "Speaker"'])])
            document=controls.read('native-panel.json')
            self.assertTrue(document['rows'][1]['section'])
            self.assertEqual(document['rows'][2]['text'],'My "Speaker"')
            self.assertTrue(document['rows'][2]['selected'])
            self.assertEqual(controls.read('volume.json')[2],['output','My "Speaker"'])
            controls.render_rows('bluetooth',[('Bluetooth · On',None),('Disconnect Headphones',['bluetooth-device','--disconnect','private-address'])])
            row=controls.read('native-panel.json')['rows'][1]
            self.assertEqual((row['text'],row['detail'],row['hint']),('Headphones','Connected','Disconnect'))
            self.assertEqual(controls.read('bluetooth.json')[1],['bluetooth-device','--disconnect','private-address'])

    def test_hidden_pin_releases_hover_and_click_after_space_change(self):
        for clicked in (False,True):
            with self.subTest(clicked=clicked), tempfile.TemporaryDirectory() as temp, \
                 patch.object(controls,'STATE',Path(temp)/'bar'), patch.object(controls,'native_controls'), \
                 patch.object(controls,'fresh_rows',return_value=[('GPU',None)]), patch.object(controls.time,'sleep'):
                controls.store('active.json',{'name':'volume','request':'old','time':time.time()-1,'pinned':True})
                controls.store('hover.json',[1,'volume'])
                (Path(temp)/'status.json').write_text(json.dumps({'healthy':True,'updated':time.time(),'controls':{'visible':False}}))
                controls.show('gpu',clicked=clicked)
                self.assertEqual(controls.read('native-panel.json')['name'],'gpu')
                self.assertEqual(controls.read('native-panel.json')['pinned'],clicked)

    def test_visible_or_unconfirmed_pin_is_not_stolen_by_hover(self):
        for case in ('visible','stale','preceding-sample','unhealthy','missing'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temp, \
                 patch.object(controls,'STATE',Path(temp)/'bar'), patch.object(controls,'native_controls') as native:
                now=time.time()
                controls.store('active.json',{'name':'volume','request':'old','time':now-1,'pinned':True})
                status={'healthy':True,'updated':now,'controls':{'visible':case=='visible'}}
                if case=='stale': status['updated']=now-10
                if case=='preceding-sample': status['updated']=now-2
                if case=='unhealthy': status['healthy']=False
                if case!='missing': (Path(temp)/'status.json').write_text(json.dumps(status))
                controls.show('gpu')
                self.assertEqual(controls.read('active.json')['name'],'volume'); native.assert_not_called()

    def test_native_picker_handoff_dismisses_custom_panel_without_reopening_it(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)), \
             patch.object(controls,'native_controls') as native, patch.object(controls,'native_calendar'), \
             patch.object(controls,'fresh_rows') as fresh:
            controls.store('hover.json',[1,'wifi'])
            controls.render_rows('wifi',[('Wi-Fi · Connected',None),('Available networks & connection…',['native','Wi-Fi'])])
            revision=controls.read('native-panel.json')['revision']; native.reset_mock()
            def action(selected):
                self.assertEqual(selected,['native','Wi-Fi'])
                self.assertEqual(controls.read('active.json'),{})
                self.assertEqual(native.call_args,unittest.mock.call('hide'))
            with patch.object(controls,'action',side_effect=action): controls.native_action('native-action','wifi','1',revision)
            fresh.assert_not_called(); self.assertEqual(controls.read('hover.json')[1],None)
            self.assertEqual(native.call_args_list,[unittest.mock.call('hide')])

    def test_native_picker_failure_uses_a_fresh_request_and_keeps_actions(self):
        rows=[('Wi-Fi · Connected',None),('Available networks & connection…',['native','Wi-Fi'])]
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)), \
             patch.object(controls,'native_controls'), patch.object(controls,'native_calendar'), \
             patch.object(controls,'fresh_rows',return_value=rows.copy()), patch.object(controls,'action',side_effect=ValueError('Permission unavailable')):
            controls.store('hover.json',[1,'wifi']); controls.render_rows('wifi',rows)
            revision=controls.read('native-panel.json')['revision']
            controls.native_action('native-action','wifi','1',revision)
            current=controls.read('native-panel.json')
            self.assertNotEqual(current['request'],'1'); self.assertTrue(current['pinned'])
            self.assertIn('unavailable',current['rows'][1]['text'])
            self.assertTrue(current['rows'][-1]['action'])

    def test_apple_and_app_name_open_native_menus_only_on_click(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp); log=directory/'menu-calls'
            hook=directory/'shell-hook'
            hook.write_text('sketchybar() { :; }\npython3() { :; }\n')
            edge=directory/'dotfiles/desktop/desktop-edge'; edge.parent.mkdir(parents=True)
            edge.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$MENU_LOG"\n')
            edge.chmod(0o700)
            for name,index in (('apple',0),('front_app',1)):
                for event in ('mouse.entered','mouse.exited'):
                    subprocess.run(['bash',str(ROOT/'.config/sketchybar/plugins/status.sh')],
                        env=dict(os.environ,BASH_ENV=str(hook),MENU_LOG=str(log),
                                 XDG_STATE_HOME=temp,NAME=name,SENDER=event),check=True,timeout=3)
                self.assertFalse(log.exists())
                subprocess.run(['bash',str(ROOT/'.config/sketchybar/plugins/status.sh')],
                    env=dict(os.environ,BASH_ENV=str(hook),MENU_LOG=str(log),
                             XDG_STATE_HOME=temp,NAME=name,SENDER='mouse.clicked'),check=True,timeout=3)
                self.assertEqual(log.read_text(),f'--app-menu {index}\n')
                log.unlink()

    def open_level_control(self, root, name, pinned=False):
        controls.store('hover.json', [1, name])
        controls.store('pin.json', {'request':'1', 'pinned':pinned})
        controls.store('anchor.json', {'request':'1', 'anchors':[dict(x=1200,y=4,width=40,height=34)]})
        controls.render_rows(name, [(('Sound' if name=='volume' else 'Display')+' · 50%', None)])
        (root/'status.json').write_text(json.dumps({'updated':time.time(),
            'controls':{'visible':True,'name':name}}))

    def test_system_level_changes_refresh_visible_hover_and_pinned_sliders(self):
        for name in ('brightness','volume'):
            for pinned in (False,True):
                with self.subTest(name=name,pinned=pinned), tempfile.TemporaryDirectory() as temp, \
                     patch.object(controls,'STATE',Path(temp)/'bar'), patch.object(controls,'native_controls') as native, \
                     patch.object(controls,'panel_rows',return_value=[('Level · 70%',None)]):
                    self.open_level_control(Path(temp),name,pinned)
                    native.reset_mock()
                    before=controls.read('native-panel.json')
                    self.assertTrue(controls.refresh_open(name))
                    after=controls.read('native-panel.json')
                    self.assertEqual(after['slider'],70)
                    for key in ('name','request','pinned','anchors'):
                        self.assertEqual(after[key],before[key])
                    native.assert_called_once_with()

    def test_network_change_refreshes_only_current_visible_wifi_request(self):
        for case in ('visible','hidden','stale','dismissed','other'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temp, \
                 patch.object(controls,'STATE',Path(temp)/'bar'), patch.object(controls,'native_controls') as native, \
                 patch.object(controls,'panel_rows',return_value=[('Wi-Fi · Connected',None),('Address · 192.0.2.2',None)]) as rows:
                root=Path(temp); self.open_level_control(root,'wifi',True); native.reset_mock()
                before=controls.read('native-panel.json'); status=json.loads((root/'status.json').read_text())
                if case=='hidden': status['controls']['visible']=False
                elif case=='stale': status['updated']-=10
                elif case=='dismissed': controls.store('native-dismissed.json',{'request':'1'})
                elif case=='other': status['controls']['name']='volume'
                (root/'status.json').write_text(json.dumps(status))
                changed=controls.refresh_open('wifi')
                self.assertEqual(changed,case=='visible')
                if case=='visible':
                    self.assertEqual(controls.read('native-panel.json')['rows'][0]['text'],'Wi-Fi · Connected')
                    for key in ('request','name','pinned','anchors'): self.assertEqual(controls.read('native-panel.json')[key],before[key])
                else: rows.assert_not_called(); native.assert_not_called()

    def test_system_level_events_do_not_query_or_reopen_hidden_stale_or_dismissed_panes(self):
        for case in ('hidden','other','stale','dismissed','new-request'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temp, \
                 patch.object(controls,'STATE',Path(temp)/'bar'), patch.object(controls,'native_controls') as native, \
                 patch.object(controls,'panel_rows') as rows:
                root=Path(temp); self.open_level_control(root,'volume',True); native.reset_mock()
                status=json.loads((root/'status.json').read_text())
                if case=='hidden': status['controls']['visible']=False
                elif case=='other': status['controls']['name']='brightness'
                elif case=='stale': status['updated']-=10
                elif case=='dismissed': controls.store('native-dismissed.json',{'request':'1'})
                else: controls.store('hover.json',[2,'brightness'])
                (root/'status.json').write_text(json.dumps(status))
                self.assertFalse(controls.refresh_open('volume'))
                rows.assert_not_called(); native.assert_not_called()

    def test_slow_device_event_cannot_overwrite_newer_event_or_new_pane(self):
        for switch_panel in (False,True):
            with self.subTest(switch_panel=switch_panel), tempfile.TemporaryDirectory() as temp, \
                 patch.object(controls,'STATE',Path(temp)/'bar'), patch.object(controls,'native_controls'):
                root=Path(temp); self.open_level_control(root,'brightness')
                def slower_result(name):
                    if switch_panel:
                        controls.store('hover.json',[2,'volume'])
                        controls.render_rows('volume',[('Sound · 80%',None)])
                    else:
                        with patch.object(controls,'panel_rows',return_value=[('Display · 80%',None)]):
                            self.assertTrue(controls.refresh_open(name))
                    return [('Display · 60%',None)]
                with patch.object(controls,'panel_rows',side_effect=slower_result):
                    self.assertFalse(controls.refresh_open('brightness'))
                after=controls.read('native-panel.json')
                self.assertEqual(after['slider'],80)
                self.assertEqual(after['name'],'volume' if switch_panel else 'brightness')

    def test_failed_device_event_read_retains_last_good_slider(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)/'bar'), \
             patch.object(controls,'native_controls') as native, \
             patch.object(controls,'panel_rows',side_effect=OSError('transient read failure')):
            self.open_level_control(Path(temp),'brightness'); native.reset_mock()
            self.assertFalse(controls.refresh_open('brightness'))
            self.assertEqual(controls.read('native-panel.json')['slider'],50)
            native.assert_not_called()

    def test_first_key_after_open_is_not_lost_to_previous_native_status_sample(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)/'bar'), \
             patch.object(controls,'native_controls'), \
             patch.object(controls,'panel_rows',return_value=[('Display · 60%',None)]):
            root=Path(temp); self.open_level_control(root,'brightness')
            (root/'status.json').write_text(json.dumps({'updated':controls.read('active.json')['time']-0.2,
                'controls':{'visible':False,'name':'volume'}}))
            self.assertTrue(controls.refresh_open('brightness'))
            self.assertEqual(controls.read('native-panel.json')['slider'],60)

    def test_device_event_finishing_after_panel_closes_cannot_refresh_it(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)/'bar'), \
             patch.object(controls,'native_controls') as native:
            root=Path(temp); self.open_level_control(root,'brightness'); native.reset_mock()
            def closed_while_reading(name):
                (root/'status.json').write_text(json.dumps({'updated':time.time(),
                    'controls':{'visible':False,'name':name}}))
                return [('Display · 60%',None)]
            with patch.object(controls,'panel_rows',side_effect=closed_while_reading):
                self.assertFalse(controls.refresh_open('brightness'))
            self.assertEqual(controls.read('native-panel.json')['slider'],50)
            native.assert_not_called()

    def test_item_anchors_use_real_rectangles_and_reject_hidden_or_nonfinite_geometry(self):
        response={'bounding_rects':{'display-1':{'origin':[1400,4],'size':[56,40]},
            'hidden':{'origin':[-9999,-9999],'size':[1,1]},'bad':{'origin':[float('nan'),4],'size':[50,40]}}}
        with patch.dict(os.environ,NAME='cpu'), patch.object(controls,'command',return_value=json.dumps(response)):
            self.assertEqual(controls.item_anchors('cpu'),[dict(x=1400,y=4,width=56,height=40)])

    def test_click_pins_without_dwell_hover_cannot_steal_it_and_second_click_closes(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)), \
             patch.object(controls,'native_controls') as native, patch.object(controls,'native_calendar'), \
             patch.object(controls,'fresh_rows',return_value=[('Sound · 50%',None)]), patch.object(controls.time,'sleep') as sleep:
            controls.show('volume',clicked=True)
            self.assertTrue(controls.read('native-panel.json')['pinned'])
            request=controls.read('native-panel.json')['request']
            sleep.assert_not_called()
            controls.show('gpu')
            self.assertEqual(controls.read('native-panel.json')['request'],request)
            controls.show('volume',clicked=True)
            self.assertEqual(controls.read('active.json'),{})
            self.assertEqual(controls.read('hover.json')[1],None)
            self.assertIn(unittest.mock.call('hide'),native.call_args_list)

    def test_native_dismissal_ack_is_request_bound_and_allows_new_hover(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)), \
             patch.object(controls,'native_controls'), patch.object(controls,'fresh_rows',return_value=[('Sound · 50%',None)]), \
             patch.object(controls.time,'sleep'):
            controls.show('volume',clicked=True)
            request=controls.read('native-panel.json')['request']
            controls.store('native-dismissed.json',{'request':'older-request'})
            controls.show('gpu')
            self.assertEqual(controls.read('native-panel.json')['name'],'volume')
            controls.store('native-dismissed.json',{'request':request})
            controls.show('gpu')
            self.assertEqual(controls.read('native-panel.json')['name'],'gpu')
            self.assertFalse(controls.read('native-panel.json')['pinned'])

    def test_native_capacity_meters_are_bounded_and_missing_capacity_is_omitted(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)), \
             patch.object(controls,'native_controls'):
            controls.render_rows('cpu',[('CPU · 150%',None)])
            self.assertEqual(controls.read('native-panel.json')['meter'],1)
            controls.render_rows('battery',[('Battery · —%',None)])
            self.assertNotIn('meter',controls.read('native-panel.json'))
            controls.store('metrics.json',{'memory':{'ram_usage':16,'ram_total':64}})
            controls.render_rows('memory',[('Memory · 16 GiB',None)])
            self.assertEqual(controls.read('native-panel.json')['meter'],0.25)
            controls.store('metrics.json',{'memory':{'ram_usage':16,'ram_total':0}})
            controls.render_rows('memory',[('Memory · unavailable',None)])
            self.assertNotIn('meter',controls.read('native-panel.json'))

    def test_native_weather_cards_preserve_row_action_indices(self):
        cards=[{'hour':'10am','temperature':'50°F','condition':'rain','precipitation':'20%'}]
        rows=[('97750',None),('Hourly forecast · 50°F',None),('Light rain',None),('Refresh forecast',['weather-refresh'])]
        with tempfile.TemporaryDirectory() as temp, patch.object(controls,'STATE',Path(temp)), \
             patch.object(controls,'native_controls'), patch.object(controls.weather,'outlook',return_value=cards), \
             patch.object(controls,'action') as action, patch.object(controls,'fresh_rows',return_value=rows):
            controls.render_rows('weather',rows)
            descriptor=controls.read('native-panel.json')
            self.assertEqual(descriptor['forecast'],cards)
            self.assertEqual(descriptor['subtitle'],'Light rain')
            self.assertEqual(descriptor['rows'][0]['text'],'Weather · 50°F')
            self.assertNotIn('weather-refresh',json.dumps(descriptor))
            controls.native_action('native-action','weather','3',descriptor['revision'])
            action.assert_called_once_with(['weather-refresh'])

    def test_clock_events_read_current_system_time_without_seconds(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            hook = directory / 'shell-hook'
            hook.write_text('sketchybar() { printf "%s\\0" "$@" > "$CLOCK_LOG"; }\n')
            for event in ('routine', 'desktop_revealed', 'system_woke'):
                log = directory / event
                env = dict(os.environ, BASH_ENV=str(hook), CLOCK_LOG=str(log),
                           XDG_STATE_HOME=str(directory), NAME='clock', SENDER=event)
                before = datetime.now().strftime('%-I:%M %p')
                subprocess.run(['bash', str(ROOT / '.config/sketchybar/plugins/status.sh')],
                               env=env, check=True, timeout=3)
                after = datetime.now().strftime('%-I:%M %p')
                args = log.read_bytes().decode().split('\0')[:-1]
                self.assertEqual(args[:2], ['--set', 'clock'])
                self.assertIn(args[2], ('label=' + before, 'label=' + after))

    def test_theme_text_and_controls_have_readable_contrast(self):
        def luminance(hex_color):
            values = [int(hex_color[i:i+2],16)/255 for i in (0,2,4)]
            values = [v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in values]
            return sum(a*b for a,b in zip(values,(0.2126,0.7152,0.0722)))
        for theme in ('graphite','nocturne','tidal','ember','iris'):
            palette = appearance.resolve(theme,'ribbon')
            for foreground in ('foreground','muted','accent','secondary','warning','danger'):
                for background in ('surface','popup'):
                    ratio = (luminance(palette[foreground])+0.05)/(luminance(palette[background])+0.05)
                    self.assertGreaterEqual(ratio,4.5,(theme,foreground,background,ratio))
            selected=(luminance(palette['foreground'])+0.05)/(luminance(palette['selection'])+0.05)
            self.assertGreaterEqual(selected,4.5,(theme,'selection',selected))

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
        for group, drawing in (('ribbon','off'),('hardware','on'),('notifications','on'),('session','off')):
            at = argv.index(group)
            self.assertEqual(argv[at+1],'background.drawing='+drawing)
            self.assertEqual(argv[at+2], 'drawing='+drawing)
        for boundary in ('hardware', 'session', 'chronicle', 'notifications'):
            at = argv.index('gap_' + boundary)
            self.assertEqual(argv[at+1], 'drawing='+('off' if boundary=='session' else 'on'))
        self.assertNotIn('--reload',argv)
        self.assertNotIn('--remove',argv)

    def test_cached_hover_renders_without_waiting_for_device_commands(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls') as native, patch.object(controls.time, 'sleep'), \
             patch.object(controls, 'panel_rows', side_effect=AssertionError('slow device query')):
            controls.store('volume.cache.json', {'time': time.time(), 'rows': [['Sound · 50%', None]]})
            controls.show('volume')
            native.assert_called_once_with()
            self.assertEqual(controls.read('native-panel.json')['slider'], 50)

    def test_shorter_panel_replaces_previous_actions_and_rows(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls'):
            controls.render_rows('bluetooth', [('Bluetooth', None), ('Connect', ['bluetooth-power', 'on'])])
            controls.render_rows('bluetooth', [('Bluetooth', None)])
            self.assertEqual(controls.read('bluetooth.json'), [None])
            self.assertEqual(controls.read('native-panel.json')['rows'], [{'text': 'Bluetooth', 'action': False}])
            self.assertEqual((Path(temp) / 'native-panel.json').stat().st_mode & 0o777, 0o600)

    def test_leaving_before_hover_dwell_cancels_pending_popup(self):
        def during_dwell(seconds):
            if seconds == 0.12:
                controls.leave('cpu')
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls') as native, \
             patch.object(controls.time, 'sleep', side_effect=during_dwell), \
             patch.object(controls, 'panel_rows', side_effect=AssertionError('cancelled hover fetched data')):
            controls.show('cpu')
            native.assert_not_called()

    def test_repeated_hover_does_not_close_and_reopen_current_panel(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls') as native, patch.object(controls.time, 'sleep') as sleep:
            controls.render_rows('volume', [('Sound', None)])
            controls.store('volume.cache.json', {'time': time.time(), 'rows': [['Sound', None]]})
            native.reset_mock()
            controls.show('volume')
            sleep.assert_not_called()
            native.assert_called_once_with()

    def test_panel_switch_reuses_native_window_with_one_notification(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls') as native:
            controls.render_rows('cpu', [('CPU', None)])
            native.reset_mock()
            controls.render_rows('gpu', [('GPU', None)])
            native.assert_called_once_with()
            self.assertEqual(controls.read('native-panel.json')['name'], 'gpu')
            self.assertEqual(controls.read('active.json')['name'], 'gpu')

    def test_open_panel_exit_defers_to_native_pointer_geometry(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls') as native, \
             patch.object(controls.time, 'sleep') as sleep:
            controls.render_rows('cpu', [('CPU', None)])
            controls.store('hover.json', [1, 'cpu'])
            native.reset_mock()
            controls.leave('cpu')
            self.assertEqual(controls.read('active.json')['name'], 'cpu')
            native.assert_not_called()
            sleep.assert_not_called()

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
             patch.object(controls, 'native_controls'), patch.object(controls.time, 'sleep'), \
             patch.object(controls, 'fresh_rows', side_effect=newer_hover):
            controls.show('cpu')
            self.assertEqual(controls.read('active.json')['name'], 'gpu')
            self.assertEqual(controls.read('native-panel.json')['rows'][0]['text'], 'GPU')

    def test_native_descriptor_has_no_command_or_private_device_identifier(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls'):
            controls.render_rows('bluetooth', [('Bluetooth · On', None), ('Headphones', ['bluetooth-device', '--connect', 'private-address'])])
            descriptor = controls.read('native-panel.json')
            self.assertNotIn('private-address', json.dumps(descriptor))
            self.assertTrue(descriptor['rows'][1]['action'])

    def test_stale_native_action_cannot_operate_new_panel_or_replaced_row(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls'), patch.object(controls, 'action') as action:
            controls.render_rows('volume', [('Sound · 50%', None), ('Mute', ['mute', 'true'])])
            revision = controls.read('native-panel.json')['revision']
            controls.render_rows('volume', [('Sound · 50%', None), ('Unmute', ['mute', 'false'])])
            controls.native_action('native-action', 'volume', '1', revision)
            current = controls.read('native-panel.json')['revision']
            controls.native_action('native-action', 'volume', '-1', current)
            action.assert_not_called()

    def test_native_slider_uses_existing_clamped_action_and_rejects_wrong_panel(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_controls'), patch.object(controls, 'action') as action, \
             patch.object(controls, 'fresh_rows', return_value=[('Sound · 100%', None)]):
            controls.render_rows('volume', [('Sound · 50%', None)])
            revision = controls.read('native-panel.json')['revision']
            controls.native_action('native-slider', 'volume', 'nan', revision)
            action.assert_not_called()
            controls.native_action('native-slider', 'volume', '150', revision)
            action.assert_called_once_with(['volume', '150'])

    def test_calendar_pending_hover_cancels_and_reentry_keeps_calendar(self):
        def during_dwell(seconds):
            if seconds == 0.12:
                controls.leave('clock')
        with tempfile.TemporaryDirectory() as temp, patch.object(controls, 'STATE', Path(temp)), \
             patch.object(controls, 'native_calendar') as calendar, patch.object(controls, 'native_controls'), \
             patch.object(controls.time, 'sleep', side_effect=during_dwell):
            controls.show('clock')
            calendar.assert_not_called()
            controls.store('active.json', {'name': 'clock'})
            controls.show('clock')
            calendar.assert_called_once_with('')

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

    def test_failed_native_build_never_publishes_partial_app_or_changes_active_link(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / 'desktop-edge').symlink_to('previous-good-build')
            with patch.object(desktop, 'run', side_effect=RuntimeError('compiler failed')):
                with self.assertRaisesRegex(RuntimeError, 'compiler failed'):
                    desktop.compile_tools(directory)
            self.assertEqual(os.readlink(directory / 'desktop-edge'), 'previous-good-build')
            self.assertEqual(list(directory.glob('DesktopControls-*.app')), [])
            self.assertEqual(list(directory.glob('desktop-build-*')), [])

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
