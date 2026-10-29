"""Prepare relative clocks for an explanatory timeline, not a Tracy capture."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[2]/'test_output/edit_stutter_diagnosis'
result=[]
names={'dig_live':'挖沙 · 运行','dig_paused':'挖沙 · 暂停','drag_live':'拖挖 · 低频','dense_drag_live':'拖挖 · 密集'}
for run in ['short_detailed','dense_drag']:
    trace=json.loads((root/run/'trace.json').read_text(encoding='utf-8'))
    analysis=json.loads((root/run/'analysis.json').read_text(encoding='utf-8'))
    for case in analysis['cases']:
        if case['name'] not in names: continue
        raw=next(c for c in trace['cases'] if c['name']==case['name'])
        rows=[r for r in trace['rows'] if r['case']==case['name']]
        out={'key':case['name'],'label':names[case['name']],'run':run,'frames':case['frames'],'commands':[]}
        for c in case['commands']:
            inp=next(i for i in raw['inputs'] if i['command']['command_id']==c['id'])
            terminal=next(t for t in raw['terminals'] if t['command']['command_id']==c['id'])
            receipt=next(r for r in rows if r['type']=='receipt' and r['command_id']==c['id'])
            input_call=next((r for r in rows if r['type']=='input_call' and r['begin_us']<=inp['input_us']<=r['end_us']),None)
            origin=input_call['begin_us'] if input_call else inp['input_us']
            end=terminal['at_us']
            rel=lambda x:round((x-origin)/1000,6)
            times={k:rel(v) for k,v in c['phase_us'].items()}
            times.update(input=rel(inp['input_us']),callback=rel(receipt['callback_us']),settle=rel(receipt['settle_us']),publish=rel(terminal['publish_us']),terminal=rel(end))
            draw=next((r for r in rows if r['type']=='post_draw' and r['command_id']==c['id'] and r['us']>=terminal['publish_us']),None)
            if draw: times['draw']=rel(draw['us'])
            frames=[{'start':max(0,rel(r['us']-r['interval_us'])),'end':min(rel(end),rel(r['us'])),'full':r['interval_us']/1000}
                    for r in rows if r['type']=='frame' and r['us']>=origin and r['us']-r['interval_us']<end]
            batches={}
            for r in rows:
                if r['type']!='collision':continue
                for chunk,stage in r['stages'].items():
                    if stage[1]<terminal['publish_us'] or stage[3]>c['phase_us']['collision_ready']:continue
                    key=(stage[1],stage[2]);b=batches.setdefault(key,{'request':rel(stage[1]),'callback':rel(stage[2]),'applied':rel(stage[3]),'chunks':[]})
                    if chunk not in b['chunks']:b['chunks'].append(chunk)
                    b['applied']=max(b['applied'],rel(stage[3]))
            ticket=str(receipt['ticket']);gpu=[]
            # Python integer subtraction before exporting; absolute GPU ns exceed JS safe integers.
            for r in rows:
                if r['type']!='gpu':continue
                starts={}
                for mark in r['marks']:
                    name=mark['name'];parts=name.split('_')
                    if not name.startswith('edit_') or parts[2]!=ticket or parts[3]=='4':continue
                    if name.endswith('_start'):starts.setdefault(name[:-6],[]).append(mark)
                    elif name.endswith('_end') and starts.get(name[:-4]):
                        first=starts[name[:-4]].pop(0)
                        gpu.append({'name':name[:-4],'a':first['gpu_ns'],'b':mark['gpu_ns']})
            if gpu:
                zero=min(p['a'] for p in gpu)
                for p in gpu:p['start']=(p.pop('a')-zero)/1e6;p['end']=(p.pop('b')-zero)/1e6
            out['commands'].append({'id':c['id'],'tick':c['requested_tick'],'amount':c['amount_m3'],'shape':c['shape'],
                                    'times':times,'frames':frames,'collision':list(batches.values()),'gpu':gpu,
                                    'handler_ms':(input_call['end_us']-input_call['begin_us'])/1000 if input_call else None,
                                    'gpu_sum':c.get('gpu_candidate_commit_sum_ms'),'sand_sum':c.get('gpu_sand_sum_ms')})
        result.append(out)
dest=Path('C:/Users/18205/.codex/visualizations/2026/10/11/01a12b66-17f8-7540-a441-518094c6be76/dig-trace.html')
template=dest.read_text(encoding='utf-8')
dest.write_text(template.replace('/*TRACE_DATA*/',json.dumps(result,ensure_ascii=False,separators=(',',':'))),encoding='utf-8')
print(dest, dest.stat().st_size)
