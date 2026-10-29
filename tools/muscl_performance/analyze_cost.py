"""Associate whole-tick GPU spans, CPU recording and completed actual dt by batch."""
from collections import Counter
import json
import math
from pathlib import Path
import re
import statistics
import sys


def stats(values):
    values=sorted(values)
    if not values:return None
    return {'n':len(values),'mean':statistics.mean(values),**{f'p{p}':values[math.ceil(len(values)*p/100)-1] for p in (50,95,99)}}


def analyze(directory):
    data=json.loads((directory/'capture.json').read_text(encoding='utf-8'))
    metadata=data['metadata']
    manifests=json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
    dropped=Counter()
    gpu={}
    for frame in data['gpu']:
        batch=None
        began=None
        for mark in frame['marks']:
            name=mark['name']
            match=re.fullmatch(r'ue_batch_(\d+)_start',name)
            if match:batch=int(match[1]);began=None
            elif name=='sandcastle_async_water_tick_start':began=mark['gpu_ns']
            elif name=='sandcastle_async_water_tick_end':
                if batch is None or began is None:dropped['unmatched_gpu_pair']+=1;continue
                if batch in gpu:dropped['duplicate_gpu_batch']+=1;continue
                if mark['gpu_ns']<=began:dropped['nonpositive_gpu_span']+=1;continue
                gpu[batch]={'gpu_ms':(mark['gpu_ns']-began)/1e6,'timestamp_frame':frame['frame'],'gpu_start_ns':began,'gpu_end_ns':mark['gpu_ns']}
            elif re.fullmatch(r'ue_batch_\d+_end',name):batch=None;began=None
    submitted={}
    completions=[]
    starts={}
    for event in data['timeline']['events']:
        if event['event']=='submit_begin':starts[event['key']]=event['at_us']
        elif event['event']=='submit_end':submitted[event['key']]=event
        elif event['event']=='settle_end':completions.append(event)
    interval=next(r for r in metadata['intervals'] if r['phase']=='live')
    rows=[]
    previous=None
    eligible=0
    for event in completions:
        now=event['detail'].get('advanced_time_s')
        previous_time=previous['detail'].get('advanced_time_s') if previous else None
        delta=now-previous_time if now is not None and previous_time is not None else None
        tick_delta=event['detail']['tick']-previous['detail']['tick'] if previous else None
        previous=event
        if not interval['start_us']<=event['at_us']<=interval['end_us'] or tick_delta!=1:continue
        eligible+=1
        key=event['key']
        if key not in gpu:dropped['completion_without_gpu_pair']+=1;continue
        if key not in submitted or key not in starts:dropped['submission_missing']+=1;continue
        if starts[key]<interval['start_us']:dropped['submission_before_window']+=1;continue
        if delta is None or delta<=0:dropped['missing_actual_dt']+=1;continue
        details=submitted[key]['detail']
        if 'water_record_us' not in details:dropped['cpu_detail_missing']+=1;continue
        if not math.isfinite(details['water_record_us']) or details['water_record_us']<=0:dropped['invalid_cpu_span']+=1;continue
        rows.append({'batch_seq':key,'state_seq':event['detail']['state_seq'],'sim_tick':event['detail']['tick'],
                     'generation':event['detail'].get('generation'),'record_seq':details.get('record_seq'),
                     'stage':'whole_tick','candidate_slot':None,'rk_phase':None,
                     'cpu_submit_start_us':starts[key],'cpu_submit_end_us':submitted[key]['at_us'],
                     'cpu_record_start_us':None,'cpu_record_end_us':None,
                     'accepted_count':None,'rejected_count':None,'invalid_slots':None,'capacity_exhausted':None,
                     'actual_dt':delta,'advanced_time_s':now,'cpu_record_us':details['water_record_us'],
                     'coupling_path':details.get('coupling_path'),
                     'standard_callable':details['standard_callable'],**gpu[key]})
    total_sim=sum(r['actual_dt'] for r in rows)
    frames=[r for r in data['frames'] if r['phase']=='live']
    suffix=directory.name.rsplit('_',1)[-1]
    result={'run_id':directory.name,'variant':suffix[0] if suffix in ('a1','a2','b1','b2') else None,
            'matched_ticks':len(rows),'eligible_completed_ticks':eligible,'coverage':len(rows)/eligible if eligible else 0,
            'complete_sample_identity':all(r['generation'] is not None and r['record_seq'] is not None for r in rows),
            'actual_sim_s':total_sim,'gpu_ms_per_sim_s':sum(r['gpu_ms'] for r in rows)/total_sim if total_sim else None,
            'gpu_tick_ms':stats([r['gpu_ms'] for r in rows]),'cpu_record_us':stats([r['cpu_record_us'] for r in rows]),
            'all_standard_callable':all(r['standard_callable'] for r in rows),'dropped':dict(dropped),
            'all_supported_coupling_paths':all(r['standard_callable'] or r['coupling_path']=='uncoupled' for r in rows),
            'frame_ms':stats([r['frame_ms'] for r in frames]),'focused_fraction':statistics.mean(r['focused'] for r in frames),
            'window_sim_ratio':(interval['end_sim_s']-interval['start_sim_s'])/((interval['end_us']-interval['start_us'])/1e6),
            'last_error':metadata['last_error'],'source_drift':metadata['source_drift'],
            'manifest_exit':manifests['exit_code'],'user_unchanged':manifests['user_unchanged'],
            'timeline_dropped':data['timeline']['dropped'],'rows':rows,
            'limits':['Whole tick intervals include all internal stages and scheduling effects.',
                      'CPU recording uses same-thread monotonic intervals; it is not added to GPU time.',
                      'Detailed performance mode is separate from normal-window FPS.',
                      'GPU cost is normalized only by matched completed batches and their actual time deltas.']}
    result['valid']=bool(rows) and result['complete_sample_identity'] and result['coverage']>=0.9 and result['all_supported_coupling_paths'] and not result['last_error'] and not result['source_drift'] and not manifests['source_drift'] and result['manifest_exit']==0 and result['user_unchanged'] and not result['timeline_dropped'] and not manifests.get('engine_errors')
    (directory/'cost_analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('rows','limits')}))
    return result


if __name__=='__main__':
    raise SystemExit(0 if analyze(Path(sys.argv[1]))['valid'] else 1)
