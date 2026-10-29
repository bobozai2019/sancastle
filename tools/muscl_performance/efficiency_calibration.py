"""Audit unchanged-process calibration without waiving focus or drift gates."""
import argparse
import json
from pathlib import Path
import statistics
from analyze_cost import analyze

def audit(a, b):
    rows=[]; failures=[]
    for directory in (a,b):
        cost=analyze(directory)
        capture=json.loads((directory/'capture.json').read_text(encoding='utf-8'))
        manifest=json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
        frames=[r for r in capture['frames'] if r['phase']=='live']
        row={'run':directory.name,'cost':cost['gpu_ms_per_sim_s'],
             'cpu_record_us':cost['cpu_record_us']['mean'] if cost['cpu_record_us'] else None,
             'frame_mean_ms':cost['frame_ms']['mean'],
             'focused_fraction':cost['focused_fraction'],
             'source_hashes':manifest['source_hashes'],
             'runner_sha256':manifest['runner_sha256'],
             'parameters':manifest['parameter_initial_sha256'],
             'engine':manifest['engine_sha256'],
             'focus_lost_us':[r['us'] for r in frames if not r['focused']]}
        if not cost['valid']:failures.append(directory.name+':invalid_cost')
        if not frames or row['focus_lost_us']:failures.append(directory.name+':focus_lost')
        rows.append(row)
    for field in ('source_hashes','runner_sha256','parameters','engine'):
        if rows[0][field]!=rows[1][field]:failures.append('identity_mismatch:'+field)
    noise={}
    for field in ('cost','cpu_record_us','frame_mean_ms'):
        values=[r[field] for r in rows]
        noise[field]=abs(values[0]-values[1])/statistics.mean(values) if all(values) else None
    return {'valid':not failures,'failures':failures,'observed_relative_difference':noise,
            'frozen_noise':noise if not failures else None,'runs':rows,
            'limits':['Observed difference in an invalid pair is not a valid noise baseline.',
                      'No GPU utilization or full-frame coverage is inferred from whole-tick timestamps.']}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--a',type=Path,required=True);p.add_argument('--b',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();result=audit(args.a,args.b)
    with args.output.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2)
    print(json.dumps({k:v for k,v in result.items() if k!='runs'}))
    raise SystemExit(not result['valid'])
