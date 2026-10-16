"""Independent byte identity and legal final-field audit for direct entries."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--evidence',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    data=json.loads(args.evidence.read_text(encoding='utf-8'));checks=[]
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    for index in data['raw_index']:
        check(index['tag']+'_all27',len(index['fields'])==27)
        for name,record in index['fields'].items():
            payload=Path(record['path']).read_bytes()
            check(index['tag']+'_'+name+'_identity',len(payload)==record['bytes'] and hashlib.sha256(payload).hexdigest()==record['sha256'])
        if not index['tag'].endswith(('_final_anchor','_final_restored')):continue
        def field(name,dtype='<f4'):
            return np.frombuffer(Path(index['fields'][name]['path']).read_bytes(),dtype=dtype)
        for name in ['sand','spare_sand','water','spare_water','sediment','spare_sediment']:
            value=field(name);check(index['tag']+'_'+name+'_legal',len(value)==65536 and np.isfinite(value).all() and (value>=0).all())
        for name in ['momentum_x','momentum_z','spare_momentum_x','spare_momentum_z']:
            value=field(name);check(index['tag']+'_'+name+'_finite',len(value)==65536 and np.isfinite(value).all())
        for name in ['wetness','compaction','spare_wetness','spare_compaction']:
            value=field(name,'<f2');check(index['tag']+'_'+name+'_range',len(value)==65536 and np.isfinite(value).all() and ((value>=0)&(value<=1)).all())
        tag=field('mold_support_0').reshape(-1,2);other=field('mold_support_1').reshape(-1,2);sand=field('sand')
        check(index['tag']+'_support_valid',np.array_equal(tag,other) and np.isfinite(tag).all() and (tag[:,0]>=0).all() and (tag[:,0]<=sand).all() and np.array_equal(tag[:,1],np.where(tag[:,0]>0,sand,0)))
        zero=tag[:,0]==0;bits=tag.view('<u4');check(index['tag']+'_support_canonical_zero',(bits[zero]==0).all())
        check(index['tag']+'_published_sand',np.array_equal(sand,field('published_sand')))
        check(index['tag']+'_published_water',np.array_equal(field('water'),field('published_water')))
    for entry in data['entries']:
        for tool in ['Castle','Wall','Shovel']:
            check(entry['key']+'_'+tool+'_actual_command',any(row['tool']==tool and any(event['terminal']['result']['status']==1 for event in row['events']) for row in entry['shape']))
        for tool in ['Dig','Fill']:
            check(entry['key']+'_'+tool+'_amount_matrix',sorted(row['amount'] for row in entry['legacy'] if row['tool']==tool and row['result'].get('status')==1)==[0.01,0.1,1.0])
        states={r['tag']:r['fields'] for r in data['raw_index']}
        before=states[entry['key']+'_final_anchor'];after=states[entry['key']+'_final_restored']
        check(entry['key']+'_restore_exact_all27',before.keys()==after.keys() and all(before[k]['sha256']==after[k]['sha256'] for k in before))
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Direct entry identities, actual commands, legal final authoritative fields and instantaneous restore; no long strict continuation or performance acceptance'}
    (args.output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('FINAL_REFERENCE',result['pass'],len(checks));raise SystemExit(0 if result['pass'] else 1)

if __name__=='__main__':main()
