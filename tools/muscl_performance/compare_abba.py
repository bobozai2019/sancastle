"""Validate independent ABBA identities and calculate the plan's noise/gain metrics."""
import argparse
import json
import math
import statistics
from pathlib import Path
from analyze_cost import analyze,stats
from context import add_arguments, resolve

parser=argparse.ArgumentParser(description=__doc__)
add_arguments(parser)
parser.add_argument('--prefix',required=True)
parser.add_argument('--mode',choices=('scene','cost','flat','input-cost'),required=True)
args=parser.parse_args()
TASK, _ = resolve(args)
evidence=TASK/'验收'
runs={}
failures=[]
for name in ('a1','b1','b2','a2'):
    directory=evidence/f'{args.prefix}_{args.mode}_{name}'
    data=json.loads((directory/'capture.json').read_text(encoding='utf-8'))
    manifest=json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
    metadata=data['metadata']
    live=next(r for r in metadata['intervals'] if r['phase']=='live')
    frames=[r for r in data['frames'] if r['phase']=='live']
    frame=stats([r['frame_ms'] for r in frames])
    row={'frame_mean_ms':frame['mean'],'frame_p95_ms':frame['p95'],'frame_p99_ms':frame['p99'],
         'simulation_ratio':(live['end_sim_s']-live['start_sim_s'])/((live['end_us']-live['start_us'])/1e6),
         'focused_fraction':statistics.mean(bool(r['focused']) for r in frames),
         'max_frame_sim_delta':max([b['sim_s']-a['sim_s'] for a,b in zip(frames,frames[1:])],default=0),
         'wall_s':(live['end_us']-live['start_us'])/1e6,'fps':1000/frame['mean']}
    row['endpoint_ratio_bound']=2*row['max_frame_sim_delta']/row['wall_s']
    for field,metric in [('render_gpu_ms','viewport_gpu_ms'),('render_cpu_ms','render_cpu_ms')]:
        values=[r.get(field) for r in frames]
        valid=bool(values) and all(isinstance(v,(int,float)) and math.isfinite(v) and v>0 for v in values)
        row[metric]=statistics.mean(values) if valid else None
        row[metric+'_missing_or_invalid']=sum(not isinstance(v,(int,float)) or not math.isfinite(v) or v<=0 for v in values)
    if args.mode in ('cost','flat','input-cost'):
        cost=analyze(directory)
        if not cost['valid']:failures.append(name+':invalid_cost')
        row.update({'gpu_ms_per_sim_s':cost['gpu_ms_per_sim_s'],'cpu_record_us':cost['cpu_record_us']['mean'] if cost['cpu_record_us'] else None})
    if manifest.get('validated_exit_code',manifest['exit_code']) or manifest.get('engine_errors') or manifest['source_drift'] or metadata['source_drift'] or metadata['last_error'] or not manifest['user_unchanged']:
        failures.append(name+':invalid_run')
    if row['focused_fraction']!=1:failures.append(name+':focus_lost')
    config={k:v for k,v in metadata['configuration'].items() if k not in ('sources','configuration_hash')}
    runs[name]={'metrics':row,'source_hashes':manifest['source_hashes'],
                'conditions':{'configuration':config,'scene':metadata.get('scene'),
                              'engine_binary_sha256':manifest.get('engine_sha256'),
                              'imports':{k:v for k,v in metadata['configuration'].get('sources',{}).items() if k.startswith('res://.godot/imported/') or k.endswith('.import')},
                              'runner_sha256':manifest.get('runner_sha256'),'launcher_sha256':manifest.get('launcher_sha256'),
                              **{k:metadata[k] for k in ('engine','adapter','driver','window','vsync','camera')}},
                'parameter_initial_sha256':manifest['parameter_initial_sha256']}
for name in ('b1','b2','a2'):
    if runs[name]['conditions']!=runs['a1']['conditions']:failures.append(name+':conditions_mismatch')
    if runs[name]['parameter_initial_sha256']!=runs['a1']['parameter_initial_sha256']:failures.append(name+':parameter_mismatch')
for a,b in [('a1','a2'),('b1','b2')]:
    if runs[a]['source_hashes']!=runs[b]['source_hashes']:failures.append(a+':variant_drift:'+b)
source_diff=[p for p in sorted(set(runs['a1']['source_hashes'])|set(runs['b1']['source_hashes'])) if runs['a1']['source_hashes'].get(p)!=runs['b1']['source_hashes'].get(p)]
comparisons={}
metrics=['frame_mean_ms','frame_p95_ms','frame_p99_ms','viewport_gpu_ms','render_cpu_ms']+(['gpu_ms_per_sim_s','cpu_record_us'] if args.mode in ('cost','flat','input-cost') else [])
for metric in metrics:
    a=[runs[n]['metrics'][metric] for n in ('a1','a2')]
    b=[runs[n]['metrics'][metric] for n in ('b1','b2')]
    if any(v is None or not math.isfinite(v) or v<=0 for v in a+b):
        comparisons[metric]={'a':a,'b':b,'status':'unknown','reason':'missing_or_invalid_samples'}
        continue
    noise=abs(a[0]-a[1])/statistics.mean(a)
    gains=[1-y/x for x,y in zip(a,b)]
    comparisons[metric]={'a':a,'b':b,'a_relative_noise':noise,'paired_gains':gains,
                         'mean_gain':1-statistics.mean(b)/statistics.mean(a),
                         'same_direction':gains[0]*gains[1]>0,
                         'both_improve':all(v>0 for v in gains),
                         'both_regress':all(v<0 for v in gains),
                         'regression_limit':max(0.02,noise),
                         'required_gain':max(0.1 if metric=='cpu_record_us' else 0.05,noise)}
progress=[]
for a,b in [('a1','b1'),('a2','b2')]:
    x,y=runs[a]['metrics'],runs[b]['metrics']
    progress.append({'a':a,'b':b,'ratio_change':y['simulation_ratio']-x['simulation_ratio'],
                     'endpoint_bound':x['endpoint_ratio_bound']+y['endpoint_ratio_bound']})
result={'valid_identities':not failures,'failures':failures,'source_differences':source_diff,
        'metrics':comparisons,'progress':progress,'runs':{k:v['metrics'] for k,v in runs.items()},
        'note':'Noise is the two unchanged A segments difference, not a confidence interval. GPU/CPU gains do not prove normal-window frame gates. Decisions require GA/G2 and all relevant G3 conditions.'}
(evidence/f'{args.prefix}_{args.mode}_comparison.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
raise SystemExit(bool(failures))
