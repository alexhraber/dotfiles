"""Cached NWS forecast for the declared ZIP point; never tracks the machine."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import fcntl
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import appearance

CONFIG = Path(__file__).resolve().parents[1] / 'weather.json'
STATE = appearance.STATE / 'bar'
INTERVAL = 900


def read(name, default=None):
    try:
        return json.loads((STATE / name).read_text())
    except (OSError, ValueError):
        return default


def save(name, data):
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = STATE / (name + '.' + str(os.getpid()))
    temporary.write_text(json.dumps(data))
    temporary.chmod(0o600)
    os.replace(temporary, STATE / name)


def fetch(url):
    if urlparse(url).scheme != 'https' or urlparse(url).netloc != 'api.weather.gov':
        raise ValueError('Weather requests must use the official HTTPS NWS API')
    request = Request(url, headers={
        'User-Agent': 'dotfiles-weather (https://github.com/alexhraber/dotfiles)',
        'Accept': 'application/geo+json'})
    with urlopen(request, timeout=5) as response:
        return json.load(response)


def cached(config):
    value = read('weather-data.json', {})
    return value if value.get('location') == config else {}


def refresh(force=False):
    config = json.loads(CONFIG.read_text())
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE / 'weather.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return cached(config)
        now = time.time()
        previous = cached(config)
        attempt = read('weather-attempt.json', {})
        if now-attempt.get('time', 0)<(60 if force else 300):
            return previous
        if not force and previous and now-previous['time']<INTERVAL:
            return previous
        save('weather-attempt.json', {'time': now})
        try:
            point = read('weather-point.json', {})
            if point.get('location')!=config or now-point.get('time', 0)>86400:
                properties = fetch(f'https://api.weather.gov/points/{config["latitude"]},{config["longitude"]}')['properties']
                point = {'location':config, 'time':now, 'hourly':properties['forecastHourly'], 'daily':properties['forecast']}
                save('weather-point.json', point)
            with ThreadPoolExecutor(max_workers=2) as pool:
                hourly, daily = list(pool.map(fetch, [point['hourly']+'?units=us', point['daily']+'?units=us']))
            hourly = hourly['properties']['periods']
            daily = daily['properties']['periods']
            if not hourly or not daily:
                raise ValueError('NWS forecast is empty')
            result = {'location':config, 'time':now, 'hourly':hourly[:24], 'daily':daily[:8]}
            save('weather-data.json', result)
            return result
        except (OSError, ValueError, KeyError, TypeError):
            # Preserve the last valid data and its original age on network failure.
            return previous


def temperature(period):
    value = period.get('temperature')
    unit = period.get('temperatureUnit', 'F')
    if isinstance(value, dict):
        unit = value.get('unitCode', '')
        value = value.get('value')
    if not isinstance(value, (int, float)) or not math.isfinite(value):
        return '—'
    if unit in ('C', 'wmoUnit:degC'):
        value = value*9/5+32
    elif unit not in ('F', 'wmoUnit:degF'):
        return '—'
    return f'{value:.0f}°F'


def periods(data):
    now = time.time()
    result = []
    for period in data.get('hourly', []):
        try:
            if datetime.fromisoformat(period['endTime']).timestamp()>now:
                result.append(period)
        except (KeyError, TypeError, ValueError):
            continue
    return result


def icon(period):
    text = period.get('shortForecast', '').lower()
    for word, glyph in (('thunder','󰖓'),('snow','󰖘'),('rain','󰖗'),('shower','󰖗'),('fog','󰖑'),('cloud','󰖐')):
        if word in text:
            return glyph
    return '󰖙' if period.get('isDaytime', True) else '󰖔'


def bar_values(data):
    available = periods(data)
    stale = time.time()-data.get('time', 0)>1800 or not available
    period = available[0] if available else next(iter(data.get('hourly', [])), {})
    label = temperature(period) + (' · cached' if stale and period else '')
    return icon(period), label, appearance.color('warning' if stale else 'secondary')


def rows():
    config = json.loads(CONFIG.read_text())
    data = cached(config)
    available = periods(data)
    if not data:
        return [(config['label'],None), ('Forecast unavailable · waiting for network',None),
                ('Refresh forecast',['weather-refresh'])]
    period = available[0] if available else data['hourly'][0]
    result = [(config['label'],None), ('Hourly forecast · '+temperature(period),None),
              (period.get('shortForecast','Unavailable'),None),
              ('Wind · '+period.get('windDirection','')+' '+period.get('windSpeed','—'),None)]
    probability = period.get('probabilityOfPrecipitation', {}).get('value')
    result.append(('Precipitation · '+(f'{probability:.0f}%' if probability is not None else '—'),None))
    for upcoming in available[1:8:3]:
        hour = datetime.fromisoformat(upcoming['startTime']).strftime('%-I %p')
        result.append((hour+' · '+temperature(upcoming)+' · '+upcoming.get('shortForecast',''),None))
    for upcoming in data['daily'][:4]:
        result.append((upcoming['name']+' · '+temperature(upcoming)+' · '+upcoming.get('shortForecast',''),None))
    age = max(0,int((time.time()-data['time'])/60))
    result += [('Cached · '+str(age)+' min old' if age>=30 or not available else 'NWS · updated '+str(age)+' min ago',None),
               ('Refresh forecast',['weather-refresh'])]
    return result[:14]


def main():
    data = refresh('--refresh' in sys.argv)
    glyph, label, color = bar_values(data)
    subprocess.run(['sketchybar','--set','weather','icon='+glyph,'label='+label,'label.color='+color],check=True,timeout=3)
    hover = read('hover.json', [])
    if len(hover)==2 and hover[1]=='weather':
        import controls
        controls.render_rows('weather',rows())


if __name__ == '__main__':
    main()
