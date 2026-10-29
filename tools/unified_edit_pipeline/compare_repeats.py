"""Freeze empirical G0 noise bounds from three unchanged-source baseline runs."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import statistics
from analyze_baseline import digest, read, stats
from analyze_workloads import summarize

def empirical_bound(values, quantum_ms):
    center=statistics.median(values)
    span=max(values)-min(values)
    # Empirical guard band, not a confidence interval or a correctness tolerance.
    margin=max(2*span,2*quantum_ms)
    return {'replicate_values_ms':values,'baseline_median_ms':center,'full_range_ms':span,
            'guard_ms':margin,'guard_relative':margin/center if center else None,
            'rule':'2*observed replicate range, minimum 2 timestamp quanta; not a statistical CI'}

def load_runs(directory):
    manifest_path=directory/'run-manifest.json'
    manifest=read(manifest_path)
    if not manifest['pass']:
        raise ValueError(f'baseline manifest incomplete or failed: {manifest_path}')
    rows={}
    for run in manifest['runs']:
        path=Path(run['result'])
        if run['drift'] or not run['pass'] or digest(path).lower()!=run['result_sha256'].lower():
            raise ValueError(f'identity or result failure: {path}')
        rows[(run['case'],run['repeat'])]=(run,read(path),summarize(path))
    return manifest,rows

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--detailed',required=True,type=Path)
    parser.add_argument('--coarse',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    dm,detail=load_runs(args.detailed)
    cm,coarse=load_runs(args.coarse)
    errors=[]
    ds={k:v for k,v in dm['sources'].items() if k.startswith(('scripts','shaders','scenes','assets')) or k=='project.godot'}
    cs={k:v for k,v in cm['sources'].items() if k.startswith(('scripts','shaders','scenes','assets')) or k=='project.godot'}
    if ds!=cs:errors.append('gameplay source inventory changed')
    comparisons=[]
    cases={}
    for case in ['dig','fill','wall','shovel']:
        detailed=[];plain=[]
        for repeat in [1,2,3]:
            a=detail[(case,repeat)];b=coarse[(case,repeat)]
            if a[2]['initial_sha256']!=b[2]['initial_sha256']:errors.append(f'initial mismatch {case} {repeat}')
            if a[2]['final_sha256']!=b[2]['final_sha256']:errors.append(f'final witness mismatch {case} {repeat}')
            detailed.append(a);plain.append(b)
            comparisons.append({'case':case,'repeat':repeat,'initial_equal':a[2]['initial_sha256']==b[2]['initial_sha256'],
                                'final_recorded_fields_equal':a[2]['final_sha256']==b[2]['final_sha256'],
                                'detailed_focus':a[2]['focus_states'],'coarse_focus':b[2]['focus_states'],
                                'detail_sha256':a[2]['sha256'],'coarse_sha256':b[2]['sha256']})
        stages={}
        names=set.intersection(*(set(r[2]['gpu_stage_dispatch_ms']) for r in detailed))
        for name in sorted(names):
            raw=[int(s['gpu_ns']) for _,data,_ in detailed for frame in data['gpu_samples'] for s in frame['spans']]
            quantum=math.gcd(*raw)/1e6 if raw else 0.000001
            stages[name]={'gpu_ms':empirical_bound([r[2]['gpu_stage_dispatch_ms'][name]['p50'] for r in detailed],quantum)}
            if all(name in r[2]['cpu_marker_stage_ms'] for r in detailed):
                stages[name]['cpu_marker_ms']=empirical_bound([r[2]['cpu_marker_stage_ms'][name]['p50'] for r in detailed],0.001)
        cases[case]={'coarse_input_frame_p50':empirical_bound([r[2]['input_only_frame_ms']['p50'] for r in plain],0.001),
                     'coarse_input_frame_p95':empirical_bound([r[2]['input_only_frame_ms']['p95'] for r in plain],0.001),
                     'detailed_input_frame_p50':empirical_bound([r[2]['input_only_frame_ms']['p50'] for r in detailed],0.001),
                     'gpu_cpu_stages':stages,
                     'focused_states_by_repeat':[r[2]['focus_states'] for r in plain],
                     'max_fps_values_by_repeat':[r[2]['max_fps_values'] for r in plain],
                     'low_processor_values_by_repeat':[r[2]['low_processor_usage_values'] for r in plain]}
    report={'role':'G0 empirical comparison guards, not final performance acceptance','pass':not errors,
            'errors':errors,'detailed_manifest_sha256':digest(args.detailed/'run-manifest.json'),
            'coarse_manifest_sha256':digest(args.coarse/'run-manifest.json'),'pairs':comparisons,'cases':cases,
            'rules':['Final comparison requires at least three alternating old/new pairs per case with recorded identical inputs/configuration.',
                     'Per metric, claim a gain only beyond its empirical guard and with direction consistent across the three pairs.',
                     'Ordinary dig/fill regressions beyond guard require attribution and repair; changing numerical tolerances is prohibited.',
                     'GPU/CPU marker dispatch samples are not whole-work totals; compare matched stage and operation.',
                     'Match or explicitly stratify focus/max_fps/low_processor/contending processes; unmatched conditions cannot prove an overall gain.',
                     'For P99, collect at least 1000 frames per condition or report unknown; these short baselines do not certify tail behavior.',
                     'Final field hash comparisons cover recorded fields, not every texture double slot or full correctness suite.']}
    with args.output.open('x',encoding='utf-8') as f:json.dump(report,f,ensure_ascii=False,indent=2)
    print(json.dumps({'pass':report['pass'],'errors':errors,'cases':{k:v['coarse_input_frame_p50'] for k,v in cases.items()}}))

if __name__=='__main__':
    main()
