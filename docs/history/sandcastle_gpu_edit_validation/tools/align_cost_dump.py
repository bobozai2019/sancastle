"""Check actual dump interval against the active cost window and recorded frame gap."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('run', type=Path)
a = p.parse_args()
trace = [json.loads(line) for line in (a.run/'cost_trace.jsonl').read_text(encoding='utf-8').splitlines()]
config = next(row for row in trace if row['type']=='configuration')
summary = next(row['value'] for row in trace if row['type']=='summary')
samples = json.loads((a.run/'process_cpu_samples.json').read_text(encoding='utf-8'))
events = []
for event in samples['dump_events']:
    begin = config['start_us'] + event['utc_start_us']-config['utc_start_us']
    end = config['start_us'] + event['utc_end_us']-config['utc_start_us']
    containing = [row for row in trace if row['type']=='frame' and row['us']-row['interval_us']<=begin and end<=row['us']]
    active = summary['start_us']<=begin<=end<summary['stop_us']
    # The timestamp pair is sequential and the system clock has finite resolution.
    # Require an ample margin before calling a same-gap association verified.
    safe = [row for row in containing if begin-(row['us']-row['interval_us'])>=2000 and row['us']-end>=2000]
    events.append(dict(event, begin_relative_us=begin, end_relative_us=end,
                       active_window=active, containing_frames=containing,
                       same_frame_gap_with_2ms_margin=bool(safe),
                       valid_for_wait_observation=event['ok'] and active and bool(safe)))
earliest = min(samples['thread_info'],key=lambda tid:samples['thread_info'][tid]['created_100ns'])
result = {'events':events,'earliest_observed_thread':int(earliest),
          'scope':'UTC/engine-clock pair with 2ms guard; dump itself perturbs scheduling; instruction contexts are instantaneous, not a duration attribution',
          'measurement':summary}
(a.run/'dump_window_alignment.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
