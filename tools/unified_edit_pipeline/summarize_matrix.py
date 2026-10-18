"""Verify complete case coverage while retaining every failed attempt."""
import argparse
import itertools
import json
from pathlib import Path
from analyze_baseline import read, digest

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('directories',nargs='+',type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    expected=set(itertools.product(['dig','fill','wall','shovel'],['straight','corner','overlap'],
                                  ['dry_paused','wet_paused','dry_realtime','wet_realtime']))
    covered={}
    failures=[]
    manifests=[]
    source_reference=None
    initial_reference=None
    errors=[]
    for directory in args.directories:
        manifest_path=directory/'run-manifest.json'
        manifest=read(manifest_path)
        manifests.append({'path':str(manifest_path.resolve()),'sha256':digest(manifest_path),
                          'pass':manifest['pass'],'classification':manifest['classification']})
        sources={k:v for k,v in manifest['sources'].items() if not k.startswith('tools')}
        if source_reference is None:
            source_reference=sources
        elif source_reference!=sources:
            errors.append(f'gameplay source inventories differ: {directory}')
        for run in manifest['runs']:
            key=(run['case'],run['pattern'],run['mode'])
            path=Path(run['result'])
            if not run['pass']:
                failures.append({'case':key,'exit_code':run['exit_code'],'result_exists':path.exists(),
                                 'stdout':str(directory/(run['name']+'.stdout.txt'))})
                continue
            if run['drift'] or digest(path).lower()!=run['result_sha256'].lower():
                errors.append(f'source or result drift: {path}')
                continue
            data=read(path)
            if not data['pass']:
                errors.append(f'inner result failed: {path}')
                continue
            initial={k:v['sha256'] for k,v in data['runtime']['initial_state'].items()}
            if initial_reference is None:
                initial_reference=initial
            elif initial_reference!=initial:
                errors.append(f'initial fields differ: {path}')
            covered[key]={'case':key,'result':str(path.resolve()),'sha256':digest(path),
                          'checks':len(data['checks']),
                          'input_open_tick_advance':data['input_open']['end_tick']-data['input_open']['start_tick'],
                          'final_accepted':data['witnesses']['accepted'],'final_rejected':data['witnesses']['rejected']}
    missing=sorted(expected-set(covered))
    report={'role':'G0 workload coverage; not full G0 or performance PASS',
            'coverage_pass':not errors and not missing,'expected':len(expected),'covered':len(covered),
            'check_count':sum(r['checks'] for r in covered.values()),'missing':missing,'errors':errors,
            'manifests':manifests,'successful_cases':[covered[k] for k in sorted(covered)],
            'failed_attempts':failures,'common_initial_fields_sha256':initial_reference,
            'limits':['An unreproduced native startup crash is preserved; it has not been diagnosed.',
                      'Focus/CPU marker/ordinary chunk observations were added in a separate later probe.',
                      'No per-case P99 claim from these short windows.']}
    with args.output.open('x',encoding='utf-8') as stream:
        json.dump(report,stream,ensure_ascii=False,indent=2)
    print(json.dumps({k:report[k] for k in ['coverage_pass','expected','covered','check_count','errors','missing']}))

if __name__=='__main__':
    main()
