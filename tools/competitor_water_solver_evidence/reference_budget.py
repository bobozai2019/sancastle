"""Encoded-field reference comparison; sampled envelopes are not universal bounds."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from evidence_contract import identity

QUANTA=dict(nx=2/255,nz=2/255,vx=8/16777215,vz=8/16777215,A=10.1/16777215,bed=10.1/16777215,B=1,source=1,sea=1)
CATEGORICAL=['B','source','sea','wet']


def codes(path):
    raw=np.fromfile(path,dtype='<u4')
    if raw.size!=512*256*4:raise ValueError('DEPENDENCY_SIZE_MISMATCH: expected 512x256 uint4')
    raw=raw.reshape(-1,4);a,b,c,d=raw.T
    fields=dict(nx=a&255,nz=(a>>8)&255,vx=(a>>16)|((b&255)<<16),vz=b>>8,A=c&0xffffff,
                bed=(c>>24)|((d&65535)<<8),B=(d>>16)&255,source=(d>>24)&15,sea=d>>28)
    packed=np.column_stack([fields['nx']|(fields['nz']<<8)|(fields['vx']<<16),
        (fields['vx']>>16)|(fields['vz']<<8),fields['A']|(fields['bed']<<24),
        (fields['bed']>>8)|(fields['B']<<16)|(fields['source']<<24)|(fields['sea']<<28)]).astype('<u4')
    if not np.array_equal(raw,packed):raise ValueError('PACKING_ROUNDTRIP_FAILED')
    fields['wet']=(fields['A'].astype(np.float64)*(10.1/16777215)>.05).astype(np.uint8)
    fields['h']=np.maximum(fields['A'].astype(np.float64)-(.05/(10.1/16777215)),0)
    return fields


def metrics(a,b):
    delta=np.abs(a.astype(np.float64)-b.astype(np.float64));index=int(np.argmax(delta))
    return dict(mae=float(delta.mean()),p99=float(np.quantile(delta,.99)),max=float(delta[index]),
                max_coordinate=[index%512,index//512],mismatches=int(np.count_nonzero(delta)))


def seal(document):
    document['sha256_scope']='canonical JSON excluding sha256, sorted keys, ASCII, compact separators'
    document['sha256']=hashlib.sha256(json.dumps(document,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()).hexdigest()
    return document


def load_budget(path):
    result=json.loads(Path(path).read_text());payload=dict(result);expected=payload.pop('sha256')
    if hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()).hexdigest()!=expected:
        raise ValueError('BUDGET_CHANGED')
    return result


def compare(budget_path,reference_id,candidate_path):
    budget=load_budget(budget_path)
    group=next((g for g in budget['references'] if g['reference_id']==reference_id),None)
    if group is None:raise ValueError('SELECTOR_MISMATCH')
    for artifact in [group['bands'],group['baseline']]:
        actual=identity(artifact['path'])
        if actual['sha256']!=artifact['sha256'] or actual['size_bytes']!=artifact['size_bytes']:raise ValueError('REFERENCE_CHANGED')
    actual=codes(candidate_path);baseline=codes(group['baseline']['path']);errors=[];results={}
    with np.load(group['bands']['path']) as bands:
        for field,rule in group['fields'].items():
            value=actual[field]
            outside=(value<bands[field+'_min'])|(value>bands[field+'_max'])
            statistics=metrics(value,baseline[field])
            limits=rule['limit_code_units']
            failed=[key for key in ['mae','p99','max'] if statistics[key]>limits[key]]
            results[field]=dict(code_metrics=statistics,pointwise_outside=int(np.count_nonzero(outside)),failed_metrics=failed)
            if np.any(outside):errors.append(dict(code='POINTWISE_REFERENCE_RANGE',field=field,count=int(outside.sum())))
            if failed:errors.append(dict(code='AGGREGATE_REFERENCE_RANGE',field=field,metrics=failed))
        for field in CATEGORICAL:
            allowed=np.any(bands[field+'_samples']==actual[field][None,:],axis=0)
            if not np.all(allowed):errors.append(dict(code='BRANCH_REFERENCE_SET',field=field,count=int(np.count_nonzero(~allowed))))
    return dict(operation_status='complete',verification_status='passed' if not errors else 'failed',reference_id=reference_id,
                candidate=identity(candidate_path),budget=identity(budget_path),errors=errors,fields=results,
                scope='Matches or fails a frozen sampled original-program envelope; not proof of universal scheduling equivalence')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--budget',required=True,type=Path)
    p.add_argument('--reference-id',required=True);p.add_argument('--candidate',required=True,type=Path)
    args=p.parse_args()
    try:result=compare(args.budget,args.reference_id,args.candidate)
    except (ValueError,FileNotFoundError) as error:
        result=dict(operation_status='failed',verification_status='failed',errors=[dict(code=str(error).split(':')[0],message=str(error),
            selector=args.reference_id,artifact_refs=[],retry_condition='Use intact frozen budget and exact reference/candidate extent')])
    print(json.dumps(result,indent=2));raise SystemExit(0 if result['verification_status']=='passed' else 1)


if __name__=='__main__':main()
