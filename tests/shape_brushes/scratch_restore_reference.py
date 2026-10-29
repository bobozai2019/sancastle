"""Audit actual scratch sentinels and distinguish evidence validity from strict recovery."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--evidence',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    data=json.loads(args.evidence.read_text());checks=[]
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    def payload(entry):
        value=Path(entry['path']).read_bytes()
        assert len(value)==entry['bytes'] and hashlib.sha256(value).hexdigest()==entry['sha256']
        return value
    for row in data['raw_index']:
        check(row['tag']+'_27_identities',len(row['fields'])==27 and all(payload(e) is not None for e in row['fields'].values()))
    for tag,fields in data['scratch_index'].items():
        check(tag+'_8_identities',len(fields)==8 and all(payload(e) is not None for e in fields.values()))
    sentinels={'edge_x':([0.375,0.75,1.25,0],65536,'<f4'),'edge_z':([-0.625,0.25,0.875,0],65536,'<f4'),'drain':([0.125],65536,'<f4'),'cfl_tiles':([7.25],1024,'<f4'),'slope_result':([0.75,0.375],65536,'<f4'),'mold_result':([0.125,0.125],65536,'<f4'),'support_flags':([1],1,'<u4'),'support_indirect':([1],6,'<u4')}
    for name,(pattern,count,dtype) in sentinels.items():
        if name not in data.get('scratch_index',{}).get('poison_written',{}):
            check(name+'_actual_sentinel_missing',False)
            continue
        value=np.frombuffer(payload(data['scratch_index']['poison_written'][name]),dtype=dtype)
        expected=np.tile(np.asarray(pattern,dtype=dtype),count)
        check(name+'_actual_sentinel',np.array_equal(value,expected))
    states={r['tag']:r['fields'] for r in data['raw_index']};anchor=states['scratch_anchor_238'];poisoned=states['poisoned_authority']
    check('poison_all_authority_unchanged',anchor.keys()==poisoned.keys() and all(anchor[n]['sha256']==poisoned[n]['sha256'] for n in anchor))
    differences=[];work_differences=[]
    for tick in [239,240,248,260,280,300]:
        direct=data['branches']['direct'][str(tick)]['fields']
        for branch in ['restored','restored_poisoned']:
            other=data['branches'][branch][str(tick)]['fields']
            changed=[name for name in direct if direct[name]['sha256']!=other[name]['sha256']]
            if changed:differences.append({'branch':branch,'tick':tick,'fields':changed})
    direct=data['scratch_index']['direct_239_work']
    for branch in ['restored','restored_poisoned']:
        other=data['scratch_index'][branch+'_239_work']
        for name in direct:
            a=np.frombuffer(payload(direct[name]),dtype='<u4');b=np.frombuffer(payload(other[name]),dtype='<u4')
            if not np.array_equal(a,b):work_differences.append({'branch':branch,'field':name,'different_words':int(np.count_nonzero(a!=b))})
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'strict_recovery_pass':not differences,'authority_differences':differences,'first_tick_work_differences':work_differences,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Identity/sentinel/invariant audit only. Observed strict differences separately reported; not proof of long determinism, absence of all hidden state, or performance acceptance.'}
    (args.output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('SCRATCH_REFERENCE evidence_valid=',result['pass'],'checks=',len(checks),'strict=',result['strict_recovery_pass'],'work_differences=',work_differences,'authority_differences=',differences)
    raise SystemExit(0 if result['pass'] else 1)

if __name__=='__main__':main()
