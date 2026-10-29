"""Analyze observer stages without treating callback latency as GPU duration."""
import json, math, sys
from collections import defaultdict, deque
from pathlib import Path

def stats(values):
    values = sorted(values)
    return {'n': len(values), 'median_ms': values[len(values)//2],
            'p99_ms': values[max(0, math.ceil(len(values)*.99)-1)], 'max_ms': values[-1]} if values else {'n': 0}

path = Path(sys.argv[1])
trace = json.loads((path/'trace.json').read_text(encoding='utf-8'))
summary = {'configuration': trace['configuration'], 'released': trace['released'], 'cases': [],
           'limits': ['Frame intervals are SceneTree callback spacing, not GPU execution or display scanout.',
                      'CPU settlement exclusive time and render-thread queue start are not instrumented.',
                      'Two physics waits include scheduling/render stalls; not exclusive physics work.',
                      'GPU timestamp instrumentation changes submission load; no formal speedup claim.',
                      'Case windows restore exact native origin, but live edit ticks diverge; no algorithm A/B.']}
for case in trace['cases']:
    rows = [r for r in trace['rows'] if r['case']==case['name']]
    frames = [r['interval_us']/1000 for r in rows if r['type']=='frame' and r['us'] <= case['stop_us']]
    groups = defaultdict(dict)
    for row in rows:
        if row['type']=='phase':
            phase=row['value']; groups[phase['command_id']][phase['phase']]=phase['at_us']
    inputs = {r['command']['command_id']:r for r in case['inputs']}
    stages = defaultdict(list)
    commands=[]
    order=['dispatch','receipt_ready','publication_ready','collision_ready','physics_one','physics_two']
    for terminal in case['terminals']:
        command=terminal['command']; cid=command['command_id']
        if cid not in inputs or cid not in groups: continue
        times=groups[cid]; spans={}
        for a,b in zip(order,order[1:]):
            if a in times and b in times: spans[a+'__'+b]=(times[b]-times[a])/1000
        if 'dispatch' in times:
            spans['input__dispatch']=(times['dispatch']-inputs[cid]['input_us'])/1000
        if 'physics_two' in times: spans['input__terminal']=(terminal['at_us']-inputs[cid]['input_us'])/1000
        receipt=next((r for r in rows if r['type']=='receipt' and r['command_id']==cid),None)
        if receipt:
            spans['dispatch__render_receipt_callback']=(receipt['callback_us']-times['dispatch'])/1000
            spans['render_callback__cpu_settle']=(receipt['settle_us']-receipt['callback_us'])/1000
        drawn=[r for r in rows if r['type']=='post_draw' and r['command_id']==cid and r['us']>=terminal['publish_us']]
        if drawn: spans['input__published_post_draw']=(min(r['us'] for r in drawn)-inputs[cid]['input_us'])/1000
        for key,value in spans.items(): stages[key].append(value)
        commands.append({'id':cid,'kind':command['kind'],'shape':command['shape'],'amount_m3':command['amount_m3'],
                         'requested_tick':command['sim_tick'],'phase_us':times,'spans_ms':spans,'status':terminal['result'].get('status')})
    collisions=[r for r in rows if r['type']=='collision']
    gpu_pairs=[]
    for row in rows:
        if row['type']!='gpu': continue
        starts=defaultdict(deque)
        for mark in row['marks']:
            name=mark['name']
            if name.endswith('_start'): starts[name[:-6]].append(mark)
            elif name.endswith('_end') and starts[name[:-4]]:
                first=starts[name[:-4]].popleft()
                gpu_pairs.append({'name':name[:-4],'frame':row['frame'],'gpu_ms':(mark['gpu_ns']-first['gpu_ns'])/1e6,
                                  'cpu_submission_ms':(mark['cpu_us']-first['cpu_us'])/1000})
    by_gpu=defaultdict(list)
    for pair in gpu_pairs:
        parts=pair['name'].split('_')
        key='_'.join(parts[:2]+parts[3:]) if pair['name'].startswith('edit_') else pair['name']
        by_gpu[key].append(pair['gpu_ms'])
    for command in commands:
        receipt=next((r for r in rows if r['type']=='receipt' and r['command_id']==command['id']),None)
        if receipt:
            ticket=str(receipt['ticket'])
            selected=[p for p in gpu_pairs if p['name'].startswith('edit_') and p['name'].split('_')[2]==ticket and p['name'].split('_')[3]!='4']
            command['gpu_candidate_commit_sum_ms']=sum(p['gpu_ms'] for p in selected) if selected else None
            command['gpu_candidate_commit_pair_count']=len(selected)
            command['gpu_sand_sum_ms']=sum(p['gpu_ms'] for p in selected if p['name'].startswith('edit_sand_')) if selected else None
            command['cpu_timestamp_submission_sum_ms']=sum(p['cpu_submission_ms'] for p in selected) if selected else None
    summary['cases'].append({'name':case['name'],'live':case['live'],'frames':stats(frames),
        'ticks':case['end_tick']-case['begin_tick'],'input_count':len(case['inputs']),'terminal_count':len(commands),'max_pending':case.get('max_pending'),'rejections':case.get('rejections',[]),
        'stages':{k:stats(v) for k,v in stages.items()},'collision_readback':stats([r['readback_ms'] for r in collisions]),
        'collision_cpu_replace':stats([r['replace_ms'] for r in collisions]),
        'input_handler_cpu':stats([(r['end_us']-r['begin_us'])/1000 for r in rows if r['type']=='input_call']),
        'independent_pick_cpu':stats([r['separate_pick_us']/1000 for r in rows if r['type']=='input_call' and 'separate_pick_us' in r]),
        'gpu_passes':{k:stats(v) for k,v in by_gpu.items()},'gpu_pairs':gpu_pairs,'commands':commands,'error':case['error']})
(path/'analysis.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
for case in summary['cases']:
    print(case['name'], 'frames=',case['frames'], 'stages=',case['stages'], 'replace=',case['collision_cpu_replace'])
