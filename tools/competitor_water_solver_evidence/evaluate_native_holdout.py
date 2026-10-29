"""Evaluate previously collected original holdouts not used in a supplementary budget."""
import argparse
import json
import shutil
from pathlib import Path
from evidence_contract import identity
from reference_budget import compare, load_budget


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',required=True,type=Path)
    ap.add_argument('--budget',required=True,type=Path)
    ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    budget=load_budget(args.budget)
    original=json.loads((args.run/'holdout.json').read_text())
    construction_paths={a['path'] for g in budget['references'] for a in g['outputs']}
    results=[];errors=[]
    for item in original['comparisons']:
        candidate=args.run/'raw'/item['reference_id']/('after_%d.bin'%item['repeat'])
        if candidate.as_posix() in construction_paths:raise ValueError('HOLDOUT_USED_IN_CONSTRUCTION')
        result=compare(args.budget,item['reference_id'],candidate)
        result['construction_path_absent']=True
        result['repeat']=item['repeat']
        path=out/(item['reference_id']+'_%d.json'%item['repeat']);path.write_text(json.dumps(result,indent=2),encoding='utf-8')
        results.append(dict(reference_id=item['reference_id'],repeat=item['repeat'],status=result['verification_status'],report=identity(path)))
        if result['verification_status']!='passed':errors.append(dict(reference_id=item['reference_id'],repeat=item['repeat'],errors=result['errors']))
    for name in ['evaluate_native_holdout.py','reference_budget.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).parent/name,out/name)
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',
        scope='Original program holdout sampled-range acceptance only. Holdout executions were not added to construction. Even a pass is not a universal scheduler bound or Godot validation.',
        budget=identity(args.budget),holdout=identity(args.run/'holdout.json'),results=results,errors=errors)
    (out/'evaluation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],errors=errors,artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(outputs=len(results),outside=len(errors))))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
