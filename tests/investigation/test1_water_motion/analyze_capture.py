"""Seal exports and obtain exact hexadecimal DXBC immediates."""
import sys, json, hashlib, ctypes, struct
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[3]
CAP=ROOT/'test_output/test1_water_motion/capture_v1'
OUT=ROOT/'test_output/test1_water_motion/analysis_v1'
OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'tests/investigation/competitor_transport'))
from analyze_transport import disassemble

def hex_disassemble(raw):
    dll=ctypes.WinDLL('d3dcompiler_47.dll'); fn=dll.D3DDisassemble
    fn.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)]
    fn.restype=ctypes.c_long
    src=ctypes.create_string_buffer(raw);blob=ctypes.c_void_p()
    hr=fn(src,len(raw),0x80|0x20,None,ctypes.byref(blob))
    if hr<0:raise RuntimeError(hr)
    vt=ctypes.cast(blob,ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    ptr=ctypes.WINFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p)(vt[3]);size=ctypes.WINFUNCTYPE(ctypes.c_size_t,ctypes.c_void_p)(vt[4]);release=ctypes.WINFUNCTYPE(ctypes.c_ulong,ctypes.c_void_p)(vt[2])
    try:return ctypes.string_at(ptr(blob),size(blob)).rstrip(b'\0').decode()
    finally:release(blob)

def decode(p):
    a=np.fromfile(p,dtype='<u4').reshape(256,512,4)
    mask=np.uint32(0xffffff)
    vx=(((a[:,:,0]>>16)|(a[:,:,1]<<16))&mask).astype(np.float64)*8/16777215-4
    vz=(a[:,:,1]>>8).astype(np.float64)*8/16777215-4
    amount=(a[:,:,2]&mask).astype(np.float64)*10.1/16777215
    floor=(((a[:,:,2]>>24)|(a[:,:,3]<<8))&mask).astype(np.float64)*10.1/16777215
    return np.stack([vx,vz,amount,floor],axis=-1)

if __name__=='__main__':
    m=json.loads((CAP/'manifest.json').read_text());assert m['pass']
    summary={'source':m['source'],'events':[]}
    seen=set()
    for r in m['events']:
        e=r['event'];out=OUT/(('e%d'%e) if e not in seen else ('e%d_repeat%d'%(e,r['sample'])));out.mkdir(exist_ok=True)
        seen.add(e)
        raw=Path(r['bytecode']['path']).read_bytes()
        (out/'instructions.txt').write_text(disassemble(raw))
        (out/'instructions_hex.txt').write_text(hex_disassemble(raw))
        c=Path(r['constants'][0]['raw']['path']).read_bytes()
        cr=[{'register':i,'float':list(struct.unpack_from('<4f',c,i*16)),'uint':list(struct.unpack_from('<4I',c,i*16))} for i in range(len(c)//16)]
        (out/'constants.json').write_text(json.dumps(cr,indent=2))
        w=next((b for b in r['bindings'] if b['resource']=='ResourceId::139573'),None)
        if w:
            a=decode(w['raw']['path']);np.save(out/'decoded.npy',a)
            speed=np.linalg.norm(a[:,:,:2],axis=-1);h=np.maximum(a[:,:,2]-.05,0)
            summary['events'].append({'event':e,'sample':r['sample'],'water_hash':w['raw']['sha256'],'speed_p':[float(x) for x in np.percentile(speed[h>.00001],[0,50,95,99,100])],
                'amount_range':[float(h.min()),float(h.max())],'floor_range':[float(a[:,:,3].min()),float(a[:,:,3].max())],
                'wet_cells':int((h>.00001).sum()),'vx_negative_wet':int(((a[:,:,0]<-.01)&(h>.00001)).sum()),'vz_negative_wet':int(((a[:,:,1]<-.01)&(h>.00001)).sum())})
    summary['repeated_e1490_equal']=m['events'][1]['bindings'][0]['raw']['sha256']==m['events'][-1]['bindings'][0]['raw']['sha256']
    summary['exports_valid']=all(hashlib.sha256(Path(x['path']).read_bytes()).hexdigest()==x['sha256'] and Path(x['path']).stat().st_size==x['bytes'] for x in m['exports'])
    (OUT/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
