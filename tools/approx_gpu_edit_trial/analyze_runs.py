import json
import math
from pathlib import Path

root = Path(__file__).resolve().parents[2]
base = root/'test_output/approx_gpu_edit_trial'
def stats(values):
    values = sorted(values)
    if not values: return {'n':0}
    return {'n':len(values),'p50':values[math.ceil(len(values)*.50)-1],'p99':values[math.ceil(len(values)*.99)-1],'max':values[-1]}

runs = []
for path in sorted(base.glob('*/result.json')):
    r = json.loads(path.read_text(encoding='utf-8'))
    stderr = (path.parent/'stderr.log').read_text(encoding='utf-8') if (path.parent/'stderr.log').exists() else ''
    row = {'run':path.parent.name,'accepted':not ('ERROR:' in stderr or r.get('failures') or r.get('error') or r.get('errors')),'original':r.get('original',False),'exact':r.get('exact',False),'diagnostic':r.get('diagnostic',bool(r.get('gpu_timestamps'))),'live':r.get('live',False),'seconds':r.get('duration_s'),'mode':r.get('mode',r.get('water_mode')),'initial_tick':r.get('initial_tick',0),'final_tick':r.get('final_tick',r.get('ticks')),'initial_hashes':r.get('initial_hashes',r.get('initial_identity',{}))}
    if path.parent.name.startswith('cost_'):
        row['controlled'] = r.get('controlled',False)
        if not row['controlled']: row['accepted'] = False
        row['frame_ms'] = stats([x[1]/1000 for x in r['frames']])
        row['inputs'] = len(r['inputs'])
        row['queue_max'] = max((x[4] for x in r['frames']),default=0)
        row['window_s'] = (r['end_us']-r['start_us'])/1e6
        if r.get('original'):
            row['input_to_return_ms'] = stats([(x['return_us']-x['input_us'])/1000 for x in r['inputs'] if x.get('result',{}).get('status')==1])
            published = {e['revision']:e['at_us'] for e in r['events'] if e.get('phase')=='published'}
            settled = {e['revision']:e['at_us'] for e in r['events'] if e.get('phase')=='settled'}
            row['input_to_publication_ack_ms'] = stats([(published[x['result']['output_revision']]-x['input_us'])/1000 for x in r['inputs'] if x.get('result',{}).get('output_revision') in published])
            row['input_to_receipt_ms'] = stats([(settled[x['result']['output_revision']]-x['input_us'])/1000 for x in r['inputs'] if x.get('result',{}).get('output_revision') in settled])
    events = r.get('events',[])
    queued = {x['command_id']:x for x in events if x.get('phase')=='queued'}
    dispatched = {x['command_id']:x for x in events if x.get('phase')=='dispatched'}
    row['admission_to_dispatch_ms'] = stats([(x['at_us']-queued[k]['at_us'])/1000 for k,x in dispatched.items() if k in queued])
    post_draw = [x for x in events if x.get('phase')=='post_draw_after_publication_request']
    publications = [x for x in events if x.get('phase')=='publication_requested']
    publication_latency = []
    for command in dispatched.values():
        after = next((e for e in publications if e['last_command']>=command['command_id'] and e['at_us']>=command['at_us']),None)
        if after and command.get('input_us'): publication_latency.append((after['at_us']-command['input_us'])/1000)
    row['input_to_publication_request_ms'] = stats(publication_latency)
    latencies = []
    for command in dispatched.values():
        after = next((e for e in post_draw if e['last_command']>=command['command_id'] and e['at_us']>=command['at_us']),None)
        if after and command.get('input_us'): latencies.append((after['at_us']-command['input_us'])/1000)
    row['input_to_post_draw_ms'] = stats(latencies)
    timestamps = r.get('gpu_timestamps',[])
    markers = {(x['frame'],x['name']):int(x.get('gpu_ns_string',x['gpu_ns'])) for x in timestamps}
    gpu = []
    batches = []
    cpu_batches = []
    cpu_edit = []
    cpu_markers = {(x['frame'],x['name']):x['cpu_us'] for x in timestamps}
    water = []
    water_groups = {}
    for (frame,name),value in markers.items():
        if not name.endswith('_end'): continue
        start = markers.get((frame,name[:-4]+'_start'))
        if start is not None:
            elapsed = (value-start)/1e6
            cpu_elapsed = cpu_markers[(frame,name)]-cpu_markers[(frame,name[:-4]+'_start')]
            if name.startswith('trial_batch_'):
                batches.append(elapsed)
                cpu_batches.append(cpu_elapsed)
            elif name.startswith('trial_'):
                gpu.append(elapsed)
                cpu_edit.append(cpu_elapsed)
            if name.startswith('edit_water_'):
                water.append(elapsed)
                parts = name.split('_')
                water_groups.setdefault('pass_'+parts[3]+'_mode_'+parts[4],[]).append(elapsed)
    row['gpu_edit_ms'] = stats(gpu)
    row['gpu_batch_with_publish_ms'] = stats(batches)
    row['cpu_batch_enqueue_us'] = stats(cpu_batches)
    row['cpu_edit_enqueue_us'] = stats(cpu_edit)
    row['gpu_water_pass_ms'] = stats(water)
    row['gpu_water_groups_ms'] = {k:stats(v) for k,v in water_groups.items()}
    row['snapshot'] = r.get('snapshot')
    runs.append(row)
(base/'run_summary.json').write_text(json.dumps(runs,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps([{k:r[k] for k in ['run','accepted','original','exact','live','seconds','mode','final_tick','gpu_edit_ms']} for r in runs],ensure_ascii=False,indent=2))
