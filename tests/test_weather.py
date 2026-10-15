from datetime import datetime, timezone
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
