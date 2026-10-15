"""One on-demand macmon sample supplies CPU/GPU temperatures and memory."""
import json
import subprocess
import controls


def labels(sample, palette=None):
    palette = palette or {'danger':'0xffff6b81', 'warning':'0xffffd166', 'muted':'0xff94a3b8'}
    memory = sample['memory']
    temperatures = sample['temp']
    result = {}
    for name in ('cpu', 'gpu'):
        temperature = float(temperatures[name + '_temp_avg'])
        load = float(sample[name + '_scaled_ratio']) * 100
        color = palette['danger'] if temperature >= 95 else palette['warning'] if temperature >= 85 else palette['muted']
        result[name] = (f'{name.upper()} {load:.0f}% {controls.fahrenheit(temperature):.0f}°F', color)
    used, total, swap = (memory[key] / 2**30 for key in ('ram_usage', 'ram_total', 'swap_usage'))
    result['memory'] = (f'RAM {used:.0f}/{total:.0f}G' + (f' · swap {swap:.1f}G' if swap else ''),
                        palette['warning'] if swap else palette['muted'])
    return result


def main():
    try:
        sample = subprocess.run(['macmon', 'pipe', '--samples', '1'], check=True,
                                capture_output=True, text=True, timeout=5)
        data = json.loads(sample.stdout)
        controls.store('metrics.json', data)
        values = labels(data, {key:controls.appearance.color(key) for key in ('danger','warning','muted')})
        messages = controls.alerts(data, controls.command('pmset', '-g', 'batt'))
        values['alerts'] = ('', controls.appearance.color('warning' if messages else 'accent'))
    except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError):
        values = {name: ('Unavailable', '0xff94a3b8') for name in ('cpu', 'gpu', 'memory')}
    args = ['sketchybar']
    for name, (label, color) in values.items():
        args += ['--set', name, 'label=' + label, 'label.color=' + color]
        if name=='alerts':
            args += ['icon.color=' + color]
    subprocess.run(args, check=True, timeout=3)
    if 'data' in locals():
        subprocess.run(['sketchybar', '--push', 'cpu.graph', str(data['cpu_scaled_ratio']),
                        '--push', 'gpu.graph', str(data['gpu_scaled_ratio']),
                        '--push', 'memory.graph', str(data['memory']['ram_usage'] / data['memory']['ram_total'])],
                       check=True, timeout=3)


if __name__ == '__main__':
    main()
