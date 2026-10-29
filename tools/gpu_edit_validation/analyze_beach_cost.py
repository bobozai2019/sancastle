"""Analyze streamed main-frame intervals, preserving the raw trace and old verdicts."""
import argparse
import hashlib
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('run', type=Path)
args = parser.parse_args()
frames, frame_rows, ticks, inputs, summary, config = [], [], [], [], None, None
terminals = []
wait_phases = {}
with (args.run / 'cost_trace.jsonl').open(encoding='utf-8') as stream:
    for line in stream:
        row = json.loads(line)
        if row['type'] == 'frame':
            frames.append(row['interval_us'] / 1000)
            frame_rows.append(row)
        elif row['type'] == 'tick':
            ticks.append(row['complete_us'])
        elif row['type'] == 'input':
            inputs.append(row)
        elif row['type'] == 'terminal':
            terminals.append(row['value'])
        elif row['type'] == 'wait_phase':
            value = row['value']
            wait_phases.setdefault(value['command_id'], {})[value['phase']] = value
        elif row['type'] == 'summary':
            summary = row['value']
        elif row['type'] == 'configuration':
            config = row
if summary is None or config is None or not frames:
    raise SystemExit('incomplete trace; no verdict produced')
ordered = sorted(frames)
quantiles = {name: ordered[max(0, math.ceil(len(ordered)*p)-1)]
             for name, p in [('p50', .5), ('p95', .95), ('p99', .99), ('p999', .999)]}
completed = sum(summary['start_us'] <= t < summary['stop_us'] for t in ticks)
assert completed == summary['completed'], 'completion-window count mismatch'
result = {'scope': 'main-thread process frame intervals, not GPU duration or first-visible latency',
          'clean_close': (args.run / 'closed.json').exists() and not (args.run / 'aborted_by_owner.json').exists(),
          'configuration': config, 'functional': summary, 'frames': len(frames),
          'frame_ms': dict(quantiles, maximum=max(frames)),
          'input_kinds': sorted({r['command']['kind'] for r in inputs}),
          'input_shapes': sorted({r['command']['shape'] for r in inputs}),
          'acceptance': 'user_v1.58',
          'candidate_performance_pass': summary['completed_hz'] >= 15 and quantiles['p99'] <= 63,
          'formal_window': config['warmup_s'] >= 30 and config['seconds'] >= 300,
          'paused_feedback': 'separate probe required; not inferred from this run'}
context_path = args.run / 'measurement_context.json'
if context_path.exists():
    result['measurement_context'] = json.loads(context_path.read_text(encoding='utf-8-sig'))
    result['eligible_for_selection'] = result['measurement_context'].get('eligible_for_selection', False)
else:
    result['eligible_for_selection'] = result['clean_close'] and '--native-wait-dump' not in config['arguments'] and '--profile-edit-passes' not in config['arguments'] and '--cost-render-timing' not in config['arguments'] and '--cost-wait-phases' not in config['arguments']
segments = {}
for row in frame_rows:
    phase = int((row['us'] - summary['start_us']) / 1000000) % 20 // 5
    segments.setdefault(['idle', 'dig', 'place', 'drag'][phase], []).append(row['interval_us']/1000)
result['segments'] = {name: {'frames':len(values), 'p99_ms':sorted(values)[math.ceil(len(values)*.99)-1],
                            'maximum_ms':max(values)} for name, values in segments.items()}
if config['backend'] == 'gpu':
    admission = {r['command']['command_id']: r['us'] for r in inputs}
    phases = {}
    for t in terminals:
        command_id = t['command']['command_id']
        if command_id not in admission or t.get('settle_us', -1) < 0 or t.get('publish_us', -1) < 0:
            continue
        for name, delta in [('input_to_settle', t['settle_us']-admission[command_id]),
                            ('settle_to_publish', t['publish_us']-t['settle_us']),
                            ('publish_to_terminal', t['at_us']-t['publish_us'])]:
            phases.setdefault(name, []).append(delta/1000)
    result['gpu_callback_phase_ms'] = {
        name: {'samples':len(values), 'p99':sorted(values)[math.ceil(len(values)*.99)-1], 'maximum':max(values)}
        for name, values in phases.items()}
    result['callback_scope'] = 'main-thread timestamps; includes queued waiting, not exclusive GPU pass duration'
    intervals, long_waits = {}, []
    order = ['dispatch', 'receipt_ready', 'publication_ready', 'collision_ready', 'physics_one', 'physics_two']
    for command_id, phases in wait_phases.items():
        for first, second in zip(order, order[1:]):
            if first not in phases or second not in phases:
                continue
            begin, end = phases[first], phases[second]
            delta = (end['at_us']-begin['at_us'])/1000
            name = first + '_to_' + second
            intervals.setdefault(name, []).append(delta)
            if delta >= 100:
                long_waits.append({'id':command_id,'phase':name,'ms':delta,
                                   'physics_frame_delta':end['physics_frame']-begin['physics_frame'],
                                   'last_collision_replace_ms':end['collision_replace_ms']})
    result['wait_phase_ms'] = {name:{'samples':len(values),'p99':sorted(values)[math.ceil(len(values)*.99)-1],
                                    'maximum':max(values)} for name, values in intervals.items()}
    result['waits_over_100ms'] = sorted(long_waits, key=lambda r:r['ms'], reverse=True)
(args.run / 'cost_analysis.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
index = [{'path': p.name, 'size': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
         for p in sorted(args.run.iterdir()) if p.is_file() and p.name != 'artifact_index.json']
(args.run / 'artifact_index.json').write_text(json.dumps(index, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
