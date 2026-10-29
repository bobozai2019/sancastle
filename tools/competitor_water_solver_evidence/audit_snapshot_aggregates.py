"""Report decoded sums/categories for the exact snapshot matrix; no conservation-law claim."""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from reference_budget import codes


def statistics(path):
    fields=codes(path);a=fields['A'].astype('f8')*(10.1/16777215)-.05;h=np.maximum(a,0)
    continuous=dict(A=a,h=h,bed=fields['bed'].astype('f8')*(10.1/16777215)-.05,vx=fields['vx'].astype('f8')*(8/16777215)-4,vz=fields['vz'].astype('f8')*(8/16777215)-4,nx=fields['nx'].astype('f8')*(2/255)-1,nz=fields['nz'].astype('f8')*(2/255)-1)
    return dict(A_code_sum=int(fields['A'].sum(dtype='u8')),A_decoded_sum=float(a.sum()),visible_h_sum=float(h.sum()),
        continuous={name:dict(min=float(value.min()),max=float(value.max()),nonfinite=int(np.count_nonzero(~np.isfinite(value)))) for name,value in continuous.items()},
        final_categories={name:{str(int(k)):int(v) for k,v in zip(*np.unique(fields[name],return_counts=True))} for name in ['B','source','sea','wet']})


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--comparison',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);args=ap.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);report=json.loads(args.comparison.read_text())
    if report['operation_status']!='complete' or report['verification_status']!='passed':raise ValueError('EXACT_COMPARISON_NOT_PASSED')
    rules=json.loads(Path(report['rules']['path']).read_text());rows=[];errors=[];cache={}
    def checked(a):
        actual=identity(a['path'])
        if actual['sha256']!=a['sha256'] or actual['size_bytes']!=a['size_bytes']:raise ValueError('ARTIFACT_CHANGED')
        if a['sha256'] not in cache:cache[a['sha256']]=statistics(a['path'])
        return cache[a['sha256']]
    for ref in rules['references']:
        before=checked(ref['snapshot']);baseline=checked(ref['baseline']);candidates=[]
        for c in report['comparisons']:
            if c['reference_id']!=ref['reference_id']:continue
            d=json.loads(Path(c['report']['path']).read_text());value=checked(d['candidate']);equal=value==baseline
            candidates.append(dict(repeat=c['repeat'],candidate=d['candidate'],aggregate_and_category_equal=equal))
            if not equal:errors.append(ref['reference_id'])
        if len(candidates)!=3:raise ValueError('REPEAT_COVERAGE')
        rows.append(dict(reference_id=ref['reference_id'],event=ref['event_id'],input_statistics=before,reference_output_statistics=baseline,candidates=candidates,
            A_decoded_delta=baseline['A_decoded_sum']-before['A_decoded_sum'],visible_h_delta=baseline['visible_h_sum']-before['visible_h_sum']))
    result=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',comparison=identity(args.comparison),rows=rows,errors=errors,
        decoding='A_decoded=code*10.1/16777215-.05; visible h=max(A_decoded,0). Code-sum and decoded sums separate. No cell-area or volume factor assumed.',
        scope='Decoded complete-output sums/nonfinite counts and final category histograms only. Equal packed output proves these aggregates equal; no new internal-branch, independent conservation, source/clamp decomposition or in-place claim.',
        source_clamp_boundary_contribution_decomposition=None)
    (out/'aggregates.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    for name in ['audit_snapshot_aggregates.py','reference_budget.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=result['verification_status'],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=result['verification_status'],identities=len(rows),comparisons=sum(len(r['candidates']) for r in rows))))


if __name__=='__main__':main()
