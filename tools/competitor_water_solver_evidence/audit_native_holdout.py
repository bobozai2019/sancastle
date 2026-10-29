"""Validate that the old-budget counterexamples really used frozen original executor/data/fences."""
import argparse
import json
import shutil
from pathlib import Path
from evidence_contract import identity
from reference_budget import load_budget


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',required=True,type=Path)
    ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    base=args.run.parent
    old=json.loads((args.run/'holdout.json').read_text())
    request=json.loads((args.run/'request.json').read_text())
    budget_path=Path(request['budget']['path']);budget=load_budget(budget_path)
    source=base/'t03_six_kernel_20261025_v4'
    frozen=json.loads((source/'manifest.json').read_text())
    expected_exe=next(a for a in frozen['artifacts'] if a['path']==(source/'sources/water_reference.exe').as_posix())
    errors=[];rows=[]
    if identity(args.run/'sources/water_reference.exe')['sha256']!=expected_exe['sha256'] or request['executor']['sha256']!=expected_exe['sha256']:
        errors.append('EXECUTOR_NOT_FROZEN_ORIGINAL')
    if identity(budget_path)['sha256']!=request['budget']['sha256']:
        errors.append('OLD_BUDGET_CHANGED')
    for rid in request['selected_reference_ids']:
        group=next(g for g in budget['references'] if g['reference_id']==rid)
        target=args.run/'raw'/rid
        log=[json.loads(s) for s in (target/'execution.jsonl').read_text().splitlines()]
        if len(log)!=8:errors.append('EXECUTION_COUNT:'+rid)
        matching=[r for r in old['runs'] if r['command'][r['command'].index('--output')+1]==str(target)]
        if len(matching)!=1 or matching[0]['exit_code']!=0:errors.append('NATIVE_RUN_NOT_COMPLETE:'+rid)
        command=matching[0]['command']
        for flag,key in [('--program','original_program'),('--input','input'),('--constants','constants')]:
            actual=identity(command[command.index(flag)+1])
            if actual['sha256']!=group[key]['sha256']:errors.append('FROZEN_DEPENDENCY_CHANGED:'+key)
        for index,e in enumerate(log):
            before=identity(target/('before_%d.bin'%index));after=identity(target/('after_%d.bin'%index))
            numeric=next(c for c in old['comparisons'] if c['reference_id']==rid and c['repeat']==index)
            check=json.loads(Path(numeric['report']['path']).read_text())
            complete=e['fence_completed']>=e['fence_ticket'] and e['repeat']==index and e['before_copy'] and e['dispatch']==[16,8,1] and e['threads']==[32,32,1]
            if not complete or before['sha256']!=group['input']['sha256'] or after['sha256']!=check['candidate']['sha256']:
                errors.append('DATA_OR_COMPLETION_NOT_PROVEN')
            if numeric['result']!='failed' or check['verification_status']!='failed' or not check['errors']:
                errors.append('EXPECTED_COUNTEREXAMPLE_NOT_OBSERVED')
            rows.append(dict(reference_id=rid,repeat=index,before=before,after=after,fence_complete=complete,old_budget_errors=check['errors']))
    for name in ['audit_native_holdout.py','reference_budget.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).parent/name,out/name)
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',
        scope='Verified 24 valid original-program outputs rejected by old sampled bounds. This validates counterexample evidence, not Godot equivalence, a new budget or universal scheduler limits.',
        holdout=identity(args.run/'holdout.json'),original_executor=expected_exe,old_budget=identity(budget_path),outputs=rows,errors=errors)
    (out/'audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],errors=errors,artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],counterexamples=len(rows),errors=errors)))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
