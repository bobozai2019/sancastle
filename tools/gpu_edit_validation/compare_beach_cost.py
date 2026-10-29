"""Validate paired warm state and nominal inputs; consumption ticks may differ."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('cpu', type=Path)
parser.add_argument('gpu', type=Path)
args = parser.parse_args()
fields = ['rock', 'sand', 'water', 'momentum_x', 'momentum_z', 'sediment', 'wetness', 'compaction', 'obstacle', 'flux']
state = {}
for prefix in ['initial', 'warm']:
    for field in fields:
        name = f'{prefix}_{field}.bin'
        a, b = args.cpu / name, args.gpu / name
        state[name] = a.is_file() and b.is_file() and a.read_bytes() == b.read_bytes()

def read(run):
    config, commands = None, []
    with (run / 'cost_trace.jsonl').open(encoding='utf-8') as stream:
        for line in stream:
            row = json.loads(line)
            if row['type'] == 'configuration':
                config = row
            elif row['type'] == 'input':
                command = row['command'].copy()
                for key in ['sim_tick', 'generation']:
                    command.pop(key, None)
                commands.append({'slot':row['slot'], 'command':command, 'error':row['error']})
    return config, commands

cpu, cpu_inputs = read(args.cpu)
gpu, gpu_inputs = read(args.gpu)
config_checks = {key: cpu.get(key) == gpu.get(key) for key in
                 ['policy', 'warmup_s', 'warm_ticks', 'initial_tick', 'trace_version', 'seconds', 'max_fps', 'physics_ticks_per_second', 'window_size', 'vsync', 'engine', 'adapter', 'wave_count', 'erosion']}
result = {'cpu':str(args.cpu.resolve()), 'gpu':str(args.gpu.resolve()),
          'states':state, 'configuration':config_checks,
          'same_nominal_inputs':cpu_inputs == gpu_inputs, 'input_count':[len(cpu_inputs), len(gpu_inputs)],
          'scope':'current fields at initialization and warm completed state; nominal inputs exclude actual consumption tick; does not prove all runtime state or continued CPU/GPU numerical equivalence',
          'pair_valid':all(state.values()) and all(config_checks.values()) and cpu_inputs == gpu_inputs}
(args.gpu / 'cost_pair_comparison.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
raise SystemExit(0 if result['pair_valid'] else 1)
