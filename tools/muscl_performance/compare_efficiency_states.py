"""Stream all original state bytes and validate the extended private dispatch ABI."""
import argparse
import json
from pathlib import Path
import struct
import zipfile

def private(raw,size):
    if len(raw)==768:
        if size!=8:raise ValueError('missing_extended_edge_records')
        return raw
    if len(raw)!=1536:raise ValueError('unexpected_trial_indirect_size')
    prefix=raw[:768]
    for slot in range(64):
        old=struct.unpack_from('<3I',prefix,slot*12)
        extra=struct.unpack_from('<3I',raw,768+slot*12)
        expected=(old[0]//(size//8),old[1]//(size//8),old[2])
        if old[0] not in (0,32) or old[1] not in (0,32) or old[2] not in (0,1):
            raise ValueError('unexpected_original_dispatch:'+str((slot,old)))
        if extra!=expected:raise ValueError('invalid_edge_dispatch:'+str((slot,old,extra,expected)))
    return prefix

def compare(a,b,a_size,b_size):
    errors=[];differences=[];mapped=0;members=0
    docs=[]
    for directory in (a,b):
        v=json.loads((directory/'variant.json').read_text(encoding='utf-8'))
        m=json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
        if not v['pass'] or not v.get('observations'):errors.append(str(directory)+':invalid_state_run')
        if m.get('validated_exit_code',m['exit_code']) or m.get('engine_errors') or m['source_drift'] or not m['user_unchanged']:
            errors.append(str(directory)+':invalid_manifest')
        docs.append(v)
    with zipfile.ZipFile(a/'states.zip') as za,zipfile.ZipFile(b/'states.zip') as zb:
        na,nb=za.namelist(),zb.namelist()
        if len(na)!=len(set(na)) or len(nb)!=len(set(nb)):errors.append('duplicate_zip_member')
        for name in sorted(set(na)|set(nb)):
            members+=1
            if name not in na or name not in nb:
                differences.append({'member':name,'reason':'missing_member'});continue
            x,y=za.read(name),zb.read(name)
            if Path(name).name=='muscl_trial_indirect.bin':
                try:x,y=private(x,a_size),private(y,b_size);mapped+=1
                except ValueError as error:errors.append(name+':'+str(error));continue
            if x!=y:
                differences.append({'member':name,'a_bytes':len(x),'b_bytes':len(y),
                    'first_byte':next((i for i,(u,v) in enumerate(zip(x,y)) if u!=v),min(len(x),len(y)))})
    observations=[ [{k:v for k,v in row.items() if k!='fields'} for row in d['observations']] for d in docs]
    if observations[0]!=observations[1]:errors.append('observations_mismatch')
    if docs[0].get('injections')!=docs[1].get('injections'):errors.append('injections_mismatch')
    return {'pass':members>0 and mapped>0 and not errors and not differences,'errors':errors,
            'difference_members':differences,'members':members,'mapped_private_members':mapped,
            'paired_captures':len(observations[0]),'scope':'All ZIP members streamed, path union, no float tolerance. Only verified trial_indirect suffix is mapped; original prefix and all other bytes remain exact.'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--a',type=Path,required=True);p.add_argument('--b',type=Path,required=True)
    p.add_argument('--a-size',type=int,choices=(8,32),default=8);p.add_argument('--b-size',type=int,choices=(8,32),required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    result=compare(a.a,a.b,a.a_size,a.b_size)
    with a.output.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2)
    print(json.dumps(result));raise SystemExit(not result['pass'])
