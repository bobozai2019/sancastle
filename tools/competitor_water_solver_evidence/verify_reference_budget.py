"""Check frozen reference-envelope implementation and corrupt-data rejection.

Reference positives validate checker coverage, not new algorithm correctness or
generalization to unseen original executions.
"""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from reference_budget import compare,load_budget


def write(path,data):path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--budget',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    p.add_argument('--deduplicate-positives',action='store_true',help='Hash-check every original file, compare identical bytes once per reference identity')
    args=p.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs']:(out/name).mkdir()
    budget=load_budget(args.budget);positives=[];negatives=[];errors=[];distinct_checks=0
    for index,ref in enumerate(budget['references']):
        if index%12==0:print(json.dumps(dict(phase='positive_reference_group',index=index)),flush=True)
        seen={}
        for output in ref['outputs']:
            actual=identity(output['path'])
            if actual['sha256']!=output['sha256'] or actual['size_bytes']!=output['size_bytes']:raise ValueError('REFERENCE_OUTPUT_CHANGED')
            reused=args.deduplicate_positives and actual['sha256'] in seen
            if reused:
                previous=seen[actual['sha256']]
                result=dict(candidate=actual,verification_status=previous['verification_status'],errors=previous['errors'])
            else:
                result=compare(args.budget,ref['reference_id'],output['path']);distinct_checks+=1;seen[actual['sha256']]=result
            positives.append(dict(reference_id=ref['reference_id'],candidate=result['candidate'],verification_status=result['verification_status'],errors=result['errors'],byte_identical_comparison_reused=bool(reused)))
            if result['errors']:errors.append(dict(code='REFERENCE_REJECTED',reference_id=ref['reference_id'],errors=result['errors']))
    still=next(r for r in budget['references'] if r['event_id']==1495 and any(p['local_reference_id']=='still_e1495' for p in r['provenance']))
    wetdry=next(r for r in budget['references'] if r['event_id']==1495 and any('correction_reference' in p['manifest']['path'] for p in r['provenance']))
    raw=np.fromfile(still['baseline']['path'],dtype='<u4').reshape(256,512,4)
    changed=raw.copy();changed[128,256,2]=(changed[128,256,2]&0xff000000)|0xffffff
    changed.tofile(out/'raw/local_A_error.bin')
    changed=raw.copy();changed[128,256,3]=(changed[128,256,3]&0xff00ffff)|(128<<16)
    changed.tofile(out/'raw/invalid_B.bin')
    changed=raw.copy();changed[128,256,3]=(changed[128,256,3]&0xf0ffffff)|(15<<24)
    changed.tofile(out/'raw/invalid_source.bin')
    wet=np.fromfile(wetdry['baseline']['path'],dtype='<u4').reshape(256,512,4)
    wet[:,::-1,:].copy().tofile(out/'raw/reversed_x.bin')
    (out/'raw/truncated.bin').write_bytes(raw.tobytes()[:128])
    cases=[('local_A_error',still,out/'raw/local_A_error.bin','POINTWISE_REFERENCE_RANGE'),
           ('invalid_B',still,out/'raw/invalid_B.bin','BRANCH_REFERENCE_SET'),
           ('invalid_source',still,out/'raw/invalid_source.bin','BRANCH_REFERENCE_SET'),
           ('reversed_x',wetdry,out/'raw/reversed_x.bin','POINTWISE_REFERENCE_RANGE'),
           ('truncated',still,out/'raw/truncated.bin','DEPENDENCY_SIZE_MISMATCH')]
    for name,ref,candidate,expected in cases:
        try:
            result=compare(args.budget,ref['reference_id'],candidate)
            observed=[e['code'] for e in result['errors']]
            passed=result['verification_status']=='failed' and expected in observed
        except ValueError as error:
            result=dict(operation_status='failed',errors=[dict(code=str(error).split(':')[0],message=str(error))])
            passed=expected in str(error)
        negatives.append(dict(name=name,expected=expected,passed=passed,result=result))
        if not passed:errors.append(dict(code='NEGATIVE_ACCEPTED',name=name))
    try:
        compare(args.budget,'missing_reference_id',still['baseline']['path']);unknown_selector=False
    except ValueError as error:unknown_selector=str(error)=='SELECTOR_MISMATCH'
    negatives.append(dict(name='unknown_reference_id',passed=unknown_selector))
    if not unknown_selector:errors.append(dict(code='UNKNOWN_SELECTOR_ACCEPTED'))
    mutated=json.loads(args.budget.read_text());mutated['rules'][0]='modified after freeze'
    write(out/'raw/changed_budget.json',mutated)
    try:
        load_budget(out/'raw/changed_budget.json');budget_changed=False
    except ValueError as error:budget_changed=str(error)=='BUDGET_CHANGED'
    negatives.append(dict(name='budget_identity_change',passed=budget_changed))
    if not budget_changed:errors.append(dict(code='CHANGED_BUDGET_ACCEPTED'))
    write(out/'derived/reference_positives.json',positives);write(out/'derived/negative_checks.json',negatives)
    for name in ['verify_reference_budget.py','reference_budget.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
    write(out/'manifest.json',dict(schema_version='1.0',run_id=out.name,operation_status='complete',verification_status='failed' if errors else 'passed',
        budget=identity(args.budget),errors=errors,reference_outputs_checked=len(positives),distinct_output_checks=distinct_checks,negative_cases=len(negatives),
        scope='Checker implementation accepts observed reference data and rejects known corruptions. Positives are source-data regression, not independent native holdout or Godot validation.',
        artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]))
    print(json.dumps(dict(reference_outputs=len(positives),negative_cases=len(negatives),errors=errors)),flush=True)
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
