"""Validate runtime schema-2 reconstruction against sampled full-state shadows."""
import argparse
import copy
import json
import shutil
from pathlib import Path
from evidence_contract import identity
from audit_runtime_pilot import water_events,closure

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args();out=args.output.resolve()
    if not str(out).isascii():raise ValueError('ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['validate_snapshot_trace.py','audit_runtime_pilot.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    raw=json.loads((args.run/'logs/events.json').read_text());events=water_events(raw);stats=json.loads((args.run/'observer_final.json').read_text());errors=closure(events,stats)
    dispatch={e['call_id']:e for e in events if e['kind']=='dispatch_enter'};shadows=[e for e in events if e['kind']=='state_shadow'];mismatches=[]
    for e in shadows:
        if e['call_id'] not in dispatch or any(e[scope]!=dispatch[e['call_id']][scope] for scope in ['parameters','bindings','global_parameters']):mismatches.append(e['call_id'])
    if not shadows or mismatches:errors.append('SHADOW_RECONSTRUCTION_MISMATCH')
    original=[e for row in raw if row.get('payload',{}).get('kind')=='water_trace' for e in row['payload']['events']]
    first=next(e for e in original if e['kind']=='dispatch_enter');key=first['state_refs']['parameters'];negatives=[]
    def test(label,changed):
        try:water_events([dict(payload=dict(kind='water_trace',events=changed))]);negatives.append(dict(case=label,rejected=False))
        except ValueError as ex:negatives.append(dict(case=label,rejected=True,error=str(ex)))
    test('missing_preceding_snapshot',[e for e in original if not(e['kind']=='state_snapshot' and e['snapshot_id']==key)])
    wrong={**first,'state_refs':{**first['state_refs'],'parameters':first['state_refs']['global_parameters']}}
    test('cross_scope_reference',[wrong if e is first else e for e in original])
    missing={k:v for k,v in first.items() if k!='state_refs'};test('missing_reference_set',[missing if e is first else e for e in original])
    incomplete={**first,'state_refs':{k:v for k,v in first['state_refs'].items() if k!='bindings'}};test('missing_binding_reference',[incomplete if e is first else e for e in original])
    duplicate=next(e for e in original if e['kind']=='state_snapshot');test('snapshot_id_reuse',[duplicate,*original])
    if not all(n['rejected'] for n in negatives):errors.append('NEGATIVE_NOT_REJECTED')
    manifest=json.loads((args.run/'manifest.json').read_text());identity_errors=[]
    for expected in manifest['artifacts']:
        actual=identity(expected['path'])
        if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:identity_errors.append(expected['path'])
    if identity_errors:errors.append('ARTIFACT_IDENTITY_MISMATCH')
    result=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',scope='Trace encoding/reconstruction only; no observer perturbation, GPU correspondence or G4 acceptance',source=identity(args.run/'manifest.json'),observer_stats=stats,shadow_count=len(shadows),shadow_mismatches=mismatches,negative_cases=negatives,artifact_identity_errors=identity_errors,errors=errors)
    (out/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8');(out/'manifest.json').write_text(json.dumps(dict(**{k:result[k] for k in ['operation_status','verification_status','scope','errors']},artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(shadows=len(shadows),mismatches=len(mismatches),negative_rejections=sum(n['rejected'] for n in negatives),errors=errors)))
    raise SystemExit(1 if errors else 0)

if __name__=='__main__':main()
