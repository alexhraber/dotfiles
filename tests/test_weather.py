from datetime import datetime, timezone, timedelta
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT / '.config/sketchybar/plugins'))
import weather


def forecast():
    now=time.time()
    hour={'temperature':50,'temperatureUnit':'F','shortForecast':'Chance Light Rain',
          'windSpeed':'5 to 10 mph','windDirection':'W',
          'probabilityOfPrecipitation':{'value':20},
          'startTime':datetime.fromtimestamp(now,timezone.utc).isoformat(),
          'endTime':datetime.fromtimestamp(now+3600,timezone.utc).isoformat()}
    return {'time':now,'hourly':[hour.copy() for _ in range(24)],
            'daily':[dict(hour,name='Tonight') for _ in range(8)]}


class WeatherTests(unittest.TestCase):
    def test_six_daily_cards_start_tomorrow_in_forecast_timezone_with_day_icons_and_lows(self):
        # UTC Saturday is still Friday evening at the pinned forecast point.
        now=datetime(2026,10,17,2,tzinfo=timezone.utc).timestamp()
        local=datetime.fromisoformat('2026-10-16T06:00:00-07:00')
        with tempfile.TemporaryDirectory() as temp, patch.object(weather,'STATE',Path(temp)), \
             patch.object(weather.time,'time',return_value=now), \
             patch.object(weather,'fetch',side_effect=AssertionError('network on hover')):
            data=forecast(); data['location']=json.loads(weather.CONFIG.read_text())
            data['daily']=[]
            for day in range(8):
                for daytime in (True,False):
                    start=local+timedelta(days=day,hours=0 if daytime else 12)
                    data['daily'].append(dict(startTime=start.isoformat(),isDaytime=daytime,
                        temperature=60+day if daytime else 40+day,temperatureUnit='F',
                        shortForecast='Sunny' if daytime else 'Rain'))
            weather.save('weather-data.json',data)
            cards=weather.daily_outlook()
        self.assertEqual([x['date'] for x in cards],[(local+timedelta(days=i)).date().isoformat() for i in range(1,7)])
        self.assertEqual(cards[0],dict(day='Sat',date='2026-10-17',high='61°F',low='41°F',condition='clear'))
        self.assertEqual(cards[-1]['day'],'Thu')

    def test_daily_cards_do_not_invent_missing_low_or_use_expired_today(self):
        now=datetime(2026,10,17,2,tzinfo=timezone.utc).timestamp()
        with tempfile.TemporaryDirectory() as temp, patch.object(weather,'STATE',Path(temp)), patch.object(weather.time,'time',return_value=now):
            data=forecast(); data['location']=json.loads(weather.CONFIG.read_text())
            data['daily']=[dict(startTime='invalid'),dict(startTime='2026-10-16T06:00:00-07:00',isDaytime=True,temperature=80),
                          dict(startTime='2026-10-17T06:00:00-07:00',isDaytime=True,temperature=10,temperatureUnit='C',shortForecast='Snow')]
            weather.save('weather-data.json',data)
            self.assertEqual(weather.daily_outlook(),[dict(day='Sat',date='2026-10-17',high='50°F',low='—',condition='snow')])

    def test_refresh_retains_fourteen_day_night_periods_for_six_future_days(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(weather,'STATE',Path(temp)):
            config=json.loads(weather.CONFIG.read_text()); data=forecast()
            weather.save('weather-point.json',dict(location=config,time=time.time(),hourly='https://api.weather.gov/hourly',daily='https://api.weather.gov/daily'))
            daily=[dict(data['daily'][0],number=i) for i in range(14)]
            def fetch(url):
                return {'properties':{'periods':data['hourly'] if '/hourly' in url else daily}}
            with patch.object(weather,'fetch',side_effect=fetch):
                self.assertEqual(len(weather.refresh()['daily']),14)

    def test_native_outlook_is_bounded_imperial_cached_and_excludes_expired_hours(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(weather,'STATE',Path(temp)), \
             patch.object(weather,'fetch',side_effect=AssertionError('network on hover')):
            data=forecast()
            data['location']=json.loads(weather.CONFIG.read_text())
            data['hourly'][0]['endTime']='2000-01-01T00:00:00+00:00'
            data['hourly'][1].update(temperature=10,temperatureUnit='C',shortForecast='Snow')
            data['hourly'][2]['probabilityOfPrecipitation']={'value':float('nan')}
            weather.save('weather-data.json',data)
            cards=weather.outlook()
            self.assertEqual(len(cards),6)
            self.assertEqual(cards[0]['temperature'],'50°F')
            self.assertEqual(cards[0]['condition'],'snow')
            self.assertEqual(cards[1]['precipitation'],'—')
            self.assertEqual(cards[2]['precipitation'],'20%')
            rows=weather.rows(include_hours=False)
            self.assertEqual(rows[-1][1],['weather-refresh'])
            self.assertEqual(len(rows),11)
            native_rows=weather.rows(include_hours=False,include_days=False)
            self.assertEqual(len(native_rows),7)
            self.assertFalse(any('Tonight' in row[0] for row in native_rows))
            self.assertEqual(weather.outlook(),cards)

    def test_native_outlook_handles_missing_cache_and_bad_hour_without_fetch(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(weather,'STATE',Path(temp)), \
             patch.object(weather,'fetch',side_effect=AssertionError('network on hover')):
            self.assertEqual(weather.outlook(),[])
            data=forecast()
            data['location']=json.loads(weather.CONFIG.read_text())
            for hour in data['hourly']:
                hour['startTime']='invalid'
            weather.save('weather-data.json',data)
            self.assertEqual(weather.outlook(),[])

    def test_fahrenheit_conversion_and_missing_values(self):
        self.assertEqual(weather.temperature({'temperature':0,'temperatureUnit':'C'}),'32°F')
        self.assertEqual(weather.temperature({'temperature':{'value':10,'unitCode':'wmoUnit:degC'}}),'50°F')
        self.assertEqual(weather.temperature({'temperature':None}),'—')
        self.assertEqual(weather.temperature({'temperature':float('nan')}),'—')

    def test_stale_forecast_is_marked_as_cached(self):
        data=forecast()
        data['time']-=1900
        self.assertEqual(weather.bar_values(data)[1],'50°F · cached')

    def test_offline_refresh_retains_last_good_data_and_backs_off(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(weather,'STATE',Path(temp)), \
             patch.object(weather,'fetch',side_effect=OSError('offline')) as fetch:
            data=forecast()
            data.update(time=time.time()-3600,location=json.loads(weather.CONFIG.read_text()))
            weather.save('weather-data.json',data)
            self.assertEqual(weather.refresh(),data)
            self.assertEqual(weather.refresh(),data)
            self.assertEqual(fetch.call_count,1)
            self.assertEqual(weather.read('weather-data.json')['time'],data['time'])

    def test_hover_reads_cache_without_network_and_keeps_refresh_action(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(weather,'STATE',Path(temp)), \
             patch.object(weather,'fetch',side_effect=AssertionError('network on hover')):
            data=forecast()
            data['location']=json.loads(weather.CONFIG.read_text())
            weather.save('weather-data.json',data)
            rows=weather.rows()
        self.assertEqual(len(rows),14)
        self.assertIn('97750',rows[0][0])
        self.assertIn('mph',rows[3][0])
        self.assertEqual(rows[-1][1],['weather-refresh'])

    def test_only_official_https_forecast_links_are_accepted(self):
        with self.assertRaises(ValueError):
            weather.fetch('http://api.weather.gov/points/0,0')
        with self.assertRaises(ValueError):
            weather.fetch('https://example.com/forecast')
