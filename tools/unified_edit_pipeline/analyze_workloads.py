"""Analyze explicit G0 observation boundaries; never infer scanout from callbacks."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

from analyze_baseline import digest, read, stats

def chunks_for(command, data):
    explicit = data['runtime'].get('command_chunks', {}).get(str(command['command_id']))
    if explicit is not None:
        return set(explicit)
    if command.get('schema_version') == 2:
        return set(range(64))  # Current backend marks all, not actual geometry.
    # Godot Vector3 is represented as text in JSON. The recorded initial chunk
    # set cannot be reconstructed safely by treating an arbitrary string as code.
    # For ordinary edits, retain observed version/chunk events without asserting
    # a full per-command collision finish when no explicit chunk mask was logged.
    return None

def summarize(path):
    data = read(path)
    frames = data['frames']
    period = [(b['at_us']-a['at_us']) / 1000 for a,b in zip(frames,frames[1:])]
    open_input = data['input_open']
    input_frames = [r for r in frames if open_input['start_at_us'] <= r['at_us'] <= open_input['end_at_us']]
    input_period = [(b['at_us']-a['at_us'])/1000 for a,b in zip(input_frames,input_frames[1:])]
    by_command = {r['command']['command_id']:r for r in data['terminals']}
    consume = {r.get('state_seq'):r for r in data['controller_events'] if r['event']=='cpu_consume'}
    complete = {r['batch_seq']:r for r in data['controller_events'] if r['event']=='gpu_complete'}
    collisions = [r for r in data['collision_events'] if r['event']=='collision_apply']
    timings = []
    for request in data['commands']:
        command = request['command']
        terminal = by_command.get(command['command_id'])
        row = {'command_id':command['command_id'], 'admitted_at_us':request['admitted_at_us']}
        if terminal:
            row['terminal_observed_at_us'] = terminal['observed_at_us']
            row['terminal_notice_ms'] = (terminal['observed_at_us']-request['admitted_at_us'])/1000
            seq = terminal['result'].get('state_seq')
            row['state_seq'] = seq
            consumed = consume.get(seq)
            if consumed:
                event = complete.get(consumed['batch_seq'])
                if event:
                    row['gpu_notice_observed_at_us'] = event['observed_at_us']
                    row['gpu_notice_ms'] = (event['observed_at_us']-request['admitted_at_us'])/1000
            needed = chunks_for(command, data)
            covered = set()
            if needed is not None:
                for event in collisions:
                    if seq is not None and event['state_seq'] >= seq:
                        covered.update(event['chunks'])
                        if needed <= covered:
                            row['collision_observed_at_us'] = event['observed_at_us']
                            row['collision_notice_ms'] = (event['observed_at_us']-request['admitted_at_us'])/1000
                            break
            else:
                row['collision_notice_ms'] = None
                row['collision_unknown_reason'] = 'ordinary command chunk mask not explicitly recorded'
        timings.append(row)
    groups = defaultdict(list)
    cpu_groups = defaultdict(list)
    for frame in data['gpu_samples']:
        for span in frame['spans']:
            name = re.sub(r'^edit_shape_\d+_(\d+)$', r'edit_shape_stage_\1', span['label'])
            if not name.startswith('edit_shape_'):
                name = span['group'] or name
            groups[name].append(span['gpu_ns']/1e6)
            if 'cpu_marker_us' in span:
                cpu_groups[name].append(span['cpu_marker_us']/1000)
    return {'result':str(path.resolve()),'sha256':digest(path),'pass':data['pass'],
            'case':data['case'],'pattern':data['pattern'],'wet':data['wet'],'realtime':data['realtime'],
            'sampling':data['sampling'],'checks':len(data['checks']),
            'target':data['target'],'cold_load_to_ready_ms':data['startup']['load_to_ready_us']/1000,
            'warmup_frames':data['startup']['warmup_frames'],
            'frame_ms':stats(period),
            'input_only_frame_ms':stats(input_period),
            'focus_states':sorted(set(r['window_focused'] for r in input_frames if 'window_focused' in r)),
            'max_fps_values':sorted(set(r['max_fps'] for r in input_frames if 'max_fps' in r)),
            'low_processor_usage_values':sorted(set(r['low_processor_usage'] for r in input_frames if 'low_processor_usage' in r)),
            'low_processor_sleep_us_values':sorted(set(r['low_processor_sleep_us'] for r in input_frames if 'low_processor_sleep_us' in r)),
            'input_open_ms':(open_input['end_at_us']-open_input['start_at_us'])/1000,
            'input_open_tick_advance':open_input['end_tick']-open_input['start_tick'],
            'input_open_sim_seconds':open_input['end_time_s']-open_input['start_time_s'],
            'queue_peak_at_observation':max((r['pending'] for r in input_frames),default=0),
            'oldest_age_ms_at_observation':max((r['oldest_outstanding_age_us']/1000 for r in input_frames),default=0),
            'drain_ms':data['witnesses']['tail_us']/1000,
            'command_timings':timings,
            'gpu_stage_dispatch_ms':{k:stats(v) for k,v in groups.items()},
            'cpu_marker_stage_ms':{k:stats(v) for k,v in cpu_groups.items()},
            'initial_sha256':{k:v['sha256'] for k,v in data['runtime']['initial_state'].items()},
            'final_sha256':data['witnesses']['field_sha256'],
            'limitations':['Notification times are CPU observation upper bounds, not GPU duration.',
                           'Physics shape replacement is observed; monitor scanout is not measured.',
                           'This workload contains 24 offered commands and is not a 1000-frame tail test.']}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory',type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args = parser.parse_args()
    manifest_path = args.directory/'run-manifest.json'
    manifest = read(manifest_path)
    runs=[]
    for run in manifest['runs']:
        path=Path(run['result'])
        if not path.exists():
            runs.append({'name':run['name'],'pass':False,'error':'missing_result'})
            continue
        if digest(path).lower()!=run['result_sha256'].lower():
            raise ValueError(f'result hash mismatch {path}')
        result=summarize(path)
        result.update({'name':run['name'],'source_drift':run['drift']})
        runs.append(result)
    with args.output.open('x',encoding='utf-8') as stream:
        json.dump({'role':'G0 workload observations, not final performance PASS',
                   'manifest':str(manifest_path.resolve()),'manifest_sha256':digest(manifest_path),
                   'analyzer_sha256':digest(Path(__file__)), 'classification':manifest['classification'],
                   'run_manifest_complete':manifest['pass'],'runs':runs},stream,ensure_ascii=False,indent=2)
    print(json.dumps({'runs':len(runs),'pass':sum(bool(r['pass']) for r in runs),'output':str(args.output)}))

if __name__=='__main__':
    main()
