"""Report timestamp differences; diagnostic GPU times are not full-load benchmarks."""
import argparse, hashlib, json
from pathlib import Path
from collections import defaultdict
p=argparse.ArgumentParser();p.add_argument('run',type=Path);p.add_argument('--report',default='interaction_probe.json');a=p.parse_args()
d=json.loads((a.run/a.report).read_text(encoding='utf-8-sig'))
passes=[]
unmatched=[]
for frame in d['timestamp_frames']:
    pending=defaultdict(list)
    for mark in frame['marks']:
        name=mark['name'];stem=name.rsplit('_',1)[0]
        if name.endswith('_start'): pending[stem].append(mark)
        elif pending[stem]:
            start=pending[stem].pop(0)
            passes.append(dict(name=stem,frame=frame['frame'],gpu_ms=(int(mark['gpu_ns'])-int(start['gpu_ns']))/1e6,
                               cpu_record_us=int(mark['cpu_us'])-int(start['cpu_us'])))
        else: unmatched.append(dict(frame=frame['frame'],name=name,reason='end_without_start'))
    for stem,starts in pending.items():
        for start in starts: unmatched.append(dict(frame=frame['frame'],name=start['name'],reason='start_without_end'))
totals=defaultdict(float)
for row in passes: totals[row['name']]+=row['gpu_ms']
commands=[]
for ordinal,row in enumerate(d['rows']):
    event,result=(row['input'],row['terminal']) if 'terminal' in row else (row['event'],row['result'])
    commands.append(dict(input=row.get('input_index',ordinal),policy=row.get('policy'),input_to_settle_ms=(result['settle_us']-event['input_us'])/1000,
                         settle_to_publish_ms=(result['publish_us']-result['settle_us'])/1000,
                         input_to_collision_ms=row['collision_feedback_ms'],shape_error_m=row.get('shape_error_m')))
report=dict(scope=d.get('scope','960x540 diagnostic four inputs')+'; timestamp capture overhead, not formal cost',
            passes=passes,unmatched_marks=unmatched,totals_ms=dict(totals),commands=commands)
out=a.run/'edit_pass_analysis.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8')
index=dict(tool=str(Path(__file__).resolve()),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
           source=a.report,source_sha256=hashlib.sha256((a.run/a.report).read_bytes()).hexdigest(),
           result=out.name,result_sha256=hashlib.sha256(out.read_bytes()).hexdigest())
(a.run/'post_pass_index.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
print(json.dumps(report['totals_ms']))
