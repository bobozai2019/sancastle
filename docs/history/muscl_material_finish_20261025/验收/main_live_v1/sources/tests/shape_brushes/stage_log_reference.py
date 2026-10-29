"""Find the first observed stage/pixel difference without claiming whole-grid coverage."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from precision_repeat_reference import compare

FIELDS=['old_sediment','old_water','flux_minus_x','flux_plus_x','flux_minus_z','flux_plus_z','obstacle','old_sand','old_wet','old_compact','new_water','stage_sand','stage_sediment','stage_wet','stage_compact','reserved']

def load_hashes(identity):
    data=Path(identity['hash_path']).read_bytes()
    assert len(data)==identity['hash_bytes'] and hashlib.sha256(data).hexdigest()==identity['hash_sha256']
    return np.frombuffer(data,dtype='<u4').reshape(identity['events'],3,64,15,2)

def mix_word(a):
    a=np.asarray(a,dtype=np.uint32).copy();a^=a>>16;a*=np.uint32(0x7feb352d);a^=a>>15;a*=np.uint32(0x846ca68b);a^=a>>16
    return a

def verify_hash_calibration(identity):
    fields=[]
    types=['<f4','<f4','<f4','u1','<f4','<f2','<f2','<f4','<f4','<f4','<f2','<f2']
    for i,f in enumerate(identity['calibration']):
        data=Path(f['path']).read_bytes();assert f['binding']==i and len(data)==f['bytes'] and hashlib.sha256(data).hexdigest()==f['sha256']
        vals=np.frombuffer(data,dtype=types[i])
        if i==3:vals=vals.astype(np.float32)/np.float32(255)
        else:vals=vals.astype('<f4')
        if i==2:fields.extend([vals.reshape(-1,4)[:,c].view('<u4') for c in range(4)])
        else:fields.append(vals.view('<u4'))
    linear=np.arange(65536,dtype=np.uint32);expected=np.zeros((64,15,2),dtype='<u4')
    for i,bits in enumerate(fields):
        a=mix_word(bits+linear*np.uint32(0x9e3779b9)+np.uint32((i*0x85ebca6b)&0xffffffff))
        b=mix_word(bits^mix_word(linear+np.uint32((i*0xc2b2ae35+0x27d4eb2f)&0xffffffff)))
        for j,v in enumerate([a,b]):
            tiles=v.reshape(8,32,8,32).transpose(0,2,1,3).reshape(64,1024)
            expected[:,i,j]=np.bitwise_xor.reduce(tiles,axis=1)
    actual=load_hashes(identity)[-1,2]
    return {'pass':bool(np.array_equal(actual,expected)),'different_words':int(np.count_nonzero(actual!=expected))}

def load_trace(p):
    identity=json.loads((p/'stage_log_identity.json').read_text())
    data=Path(identity['path']).read_bytes()
    assert len(data)==identity['bytes'] and hashlib.sha256(data).hexdigest()==identity['sha256']
    rows=np.frombuffer(data,dtype='<u4').reshape(identity['events'],3,identity['pixels_per_stage'],24)
    assert np.array_equal(rows[:,:,:,6],np.broadcast_to(np.arange(identity['events'])[:,None,None],rows[:,:,:,6].shape))
    assert np.array_equal(rows[:,:,:,7],np.broadcast_to(np.arange(3)[None,:,None],rows[:,:,:,7].shape))
    assert np.count_nonzero(rows[:,:,:,23])==0
    return identity,rows

def run(output):
    root=output.parent
    ia,a=load_trace(root/'original_a');ib,b=load_trace(root/'original_b')
    records=[json.loads((root/n/'retention_evidence.json').read_text()) for n in ['original_a','original_b']]
    checks=[]
    def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
    check('both_900_ticks',all(r['completed_ticks']==900 for r in records))
    check('same_event_count',len(a)==len(b),[len(a),len(b)])
    check('actual_original_shader_identity_same',ia['snapshot_identity']==ib['snapshot_identity'])
    for name,identity in [('a',ia),('b',ib)]:
        if 'calibration' in identity:
            audit=verify_hash_calibration(identity);check(name+'_final_full_hash_cpu_calibration',audit['pass'],audit)
    first=None;first_inputs=None;first_outputs=None
    for i in range(min(len(a),len(b))):
        for phase in range(3):
            for pixel in range(ia['pixels_per_stage']):
                x,y=a[i,phase,pixel],b[i,phase,pixel]
                assert np.array_equal(x[:8],y[:8]),'metadata diverged before values'
                bad=np.flatnonzero(x[8:]!=y[8:])
                if len(bad):
                    difference={'event':i,'tick':int(x[0]),'revision':int(x[1]),'index':int(x[2]),'stage':phase,'pixel':[int(x[4]),int(x[5])],'fields':[FIELDS[j] for j in bad],
                        'values':[{'field':FIELDS[j],'a_bits':hex(int(x[j+8])),'b_bits':hex(int(y[j+8])),'a':float(x[j+8:j+9].view('<f4')[0]),'b':float(y[j+8:j+9].view('<f4')[0])} for j in bad]}
                    if first is None:first=difference
                    if phase==0 and first_inputs is None:first_inputs=difference
                    if phase>0 and first_outputs is None and any(11<=j<=14 for j in bad):first_outputs=difference
    repeat=compare(*records)
    # Completion of a diagnostic is distinct from compatibility acceptance.
    first_hash=None
    if 'hash_path' in ia:
        ha,hb=load_hashes(ia),load_hashes(ib)
        ids=np.argwhere(np.any(ha!=hb,axis=-1))
        if len(ids):
            event,phase,tile,field=map(int,ids[0]);meta=a[event,phase,0]
            first_hash={'event':event,'tick':int(meta[0]),'revision':int(meta[1]),'stage':phase,'tile':tile,'tile_cell_bounds':[tile%8*32,tile//8*32,tile%8*32+31,tile//8*32+31],'field':FIELDS[field],'a':ha[event,phase,tile,field].tolist(),'b':hb[event,phase,tile,field].tolist()}
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'checkpoint_repeat':repeat,'first_observed_difference':first,'first_pre_sediment_difference':first_inputs,'first_post_stage_difference':first_outputs,'first_tile_hash_difference':first_hash,
            'scope':'32 fixed pixels, all three diagnostic stage snapshots per substep; extra GPU copies/dispatch can alter scheduling. First observed is not a proof of earliest whole-grid divergence or root cause.'}
    (output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');return result['pass']

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True);passed=run(args.output);print('STAGE_LOG_DIAGNOSIS_COMPLETE',passed);raise SystemExit(0 if passed else 1)
