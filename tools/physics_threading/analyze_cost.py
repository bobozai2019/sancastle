"""Derived GPU pairs, stage waits and long-frame associations; never claim causality."""
import bisect, hashlib, json, sys
from collections import defaultdict
from pathlib import Path
from summarize_cost import stats

def analyze(folder):
    folder=Path(folder);trace=json.loads((folder/'trace.json').read_text(encoding='utf-8'))
    frames=defaultdict(list);batches=defaultdict(list);phases=defaultdict(dict);gpu=defaultdict(lambda:defaultdict(list))
    gpu_unmatched=defaultdict(int)
    for line in (folder/'trace.jsonl').open(encoding='utf-8'):
        row=json.loads(line);case=row['case'];kind=row['type']
        if kind=='frame':frames[case].append(row)
        elif kind=='collision':batches[case].append(row)
        elif kind=='phase':
            mark=row['value'];phases[case].setdefault(mark['command_id'],{})[mark['phase']]=mark
        elif kind=='gpu':
            pending=defaultdict(list)
            for mark in row['marks']:
                name=mark['name'];stage=None;start=False
                if name.endswith('_start'):stage=name[:-6];start=True
                elif name.endswith('_end'):stage=name[:-4]
                elif name.startswith('vp_begin_'):stage=name[9:];start=True
                elif name.startswith('vp_end_'):stage=name[7:]
                if stage is None:continue
                if start:pending[stage].append(mark)
                elif pending[stage]:
                    begin=pending[stage].pop(0)
                    duration=(mark['gpu_ns']-begin['gpu_ns'])/1e6
                    if duration>=0:gpu[case][stage].append(duration)
                    else:gpu_unmatched[case]+=1
                else:gpu_unmatched[case]+=1
            gpu_unmatched[case]+=sum(map(len,pending.values()))
    result=[]
    for case in trace['cases']:
        name=case['name'];stage_waits=defaultdict(list)
        for marks in phases[name].values():
            sequence=['dispatch','receipt_ready','publication_ready','collision_ready','physics_one','physics_two']
            for begin,end in zip(sequence,sequence[1:]):
                if begin in marks and end in marks:stage_waits[begin+'->'+end].append((marks[end]['at_us']-marks[begin]['at_us'])/1000)
        collision=sorted(batches[name],key=lambda r:r['us']);times=[r['us'] for r in collision]
        episodes=[]
        for frame in frames[name]:
            if frame['us']>=case['stop_us'] or frame['interval_us']<=100000:continue
            low=frame['us']-frame['interval_us'];high=frame['us']
            related=collision[bisect.bisect_left(times,low):bisect.bisect_right(times,high)]
            episodes.append({'begin_us':low,'end_us':high,'frame_ms':frame['interval_us']/1000,
                'tick':frame['tick'],'pending':frame['pending'],'busy':frame['busy'],
                'collision_callbacks_in_interval':len(related),
                'callback_apply_max_ms':max((r['apply_ms'] for r in related),default=None),
                'callback_readback_max_ms':max((r['readback_ms'] for r in related),default=None)})
        result.append({'name':name,'gpu_pair_ms':{k:stats(v) for k,v in gpu[name].items()},
            'gpu_unmatched_pairs':gpu_unmatched[name],'stage_wall_ms':{k:stats(v) for k,v in stage_waits.items()},
            'long_frame_episodes':episodes})
    output={'cases':result,'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'limits':['GPU durations use only paired marks in one captured timestamp frame; sampled at 100ms',
                  'CPU phase deltas are wall waits, not per-thread CPU busy costs',
                  'frame callback associations are correlations; no GPU/CPU clock subtraction or causal attribution',
                  'missing collision callback evidence is null, never zero']}
    (folder/'stage_analysis.json').write_text(json.dumps(output,indent=2),encoding='utf-8')
    print(folder.name,[(r['name'],len(r['long_frame_episodes'])) for r in result])
    return output

if __name__=='__main__':
    for folder in sys.argv[1:]:analyze(folder)
