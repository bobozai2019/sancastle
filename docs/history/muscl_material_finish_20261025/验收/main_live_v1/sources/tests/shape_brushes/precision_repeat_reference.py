"""Compare ordinary repeatability under original and explicit-precision shader."""
import argparse
import hashlib
import json
from pathlib import Path


def compare(a,b):
    bad=[]
    for x,y in zip(a['samples'],b['samples']):
        fields=[n for n in x['fields'] if x['fields'][n]['sha256']!=y['fields'][n]['sha256']]
        if fields:bad.append({'tick':x['tick'],'fields':fields})
    traces={k:next(({'index':i,'a':x,'b':y} for i,(x,y) in enumerate(zip(a[k],b[k])) if x!=y),None) for k in ['substeps','cfl_inputs']}
    return {'exact':not bad and a['substeps']==b['substeps'] and a['cfl_inputs']==b['cfl_inputs'],'raw_differences':bad,'first_trace_differences':traces}


def run(output):
    records={n:json.loads((output.parent/n/'retention_evidence.json').read_text()) for n in ['native_a','native_b','precise_a','precise_b']}
    checks=[]
    def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
    for name,r in records.items():
        check(name+'_900_ticks_and_seven_samples',r['completed_ticks']==900 and [s['tick'] for s in r['samples']]==list(range(0,901,150)))
        check(name+'_900_trace_records',len(r['substeps'])==len(r['cfl_inputs'])==900)
        for sample in r['samples']:
            check(name+'_25_fields_'+str(sample['tick']),len(sample['fields'])==25)
            for f in sample['fields'].values():
                data=Path(f['path']).read_bytes();assert len(data)==f['bytes'] and hashlib.sha256(data).hexdigest()==f['sha256']
    native=compare(records['native_a'],records['native_b']);precise=compare(records['precise_a'],records['precise_b'])
    identities=[json.loads((output.parent/n/'precision_identity.json').read_text()) for n in ['precise_a','precise_b']]
    check('same_actual_precision_shader_identity',identities[0]==identities[1])
    check('precise_repeat_all_25_and_traces_exact',precise['exact'],precise)
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'native_repeat':native,'precise_repeat':precise,'cross_variant':compare(records['native_a'],records['precise_a']),'precision_identity':identities[0],'scope':'Precision repeatability diagnosis only. No production change, ordinary-material equivalence acceptance or root-cause proof.'}
    (output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');return result['pass']


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True);passed=run(args.output);print('PRECISION_REPEAT_DIAGNOSIS',passed);raise SystemExit(0 if passed else 1)
