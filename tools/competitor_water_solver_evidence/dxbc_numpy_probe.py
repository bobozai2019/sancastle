"""Independent float32 expression diagnostic for frozen straight-line water DXBC.

CPU hypotheses only: never original reference, shader recovery, or acceptance oracle.
Only the no-auxiliary velocity/advection subset is supported in this first probe.
"""
import argparse
import ctypes
import json
import re
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from lower_dxbc_glsl import split_args,destination,audit_defined_lanes,LANES


def fma32(a,b,c):
    """Exact binary32 FMA, using scalar C fmaf only for double-rounding midpoints."""
    a,b,c=np.broadcast_arrays(a,b,c)
    wide=a.astype('f8')*b.astype('f8')+c.astype('f8')
    rounded=np.array(wide,dtype='<f4',order='C')
    adjacent=np.nextafter(rounded,np.where(wide>rounded,np.float32(np.inf),np.float32(-np.inf)).astype('<f4'))
    midpoint=(rounded.astype('f8')+adjacent.astype('f8'))*.5
    ties=np.flatnonzero((wide==midpoint).ravel() & np.isfinite(wide).ravel())
    if len(ties):
        fn=ctypes.CDLL('ucrtbase.dll').fmaf;fn.argtypes=[ctypes.c_float]*3;fn.restype=ctypes.c_float
        out=rounded.ravel();aa,bb,cc=a.ravel(),b.ravel(),c.ravel()
        for i in ties:out[i]=fn(float(aa[i]),float(bb[i]),float(cc[i]))
    return rounded


def execute(text,water,constants,captures=(),division='rcp_mul',uniform_fold='none'):
    audit_defined_lanes(text)
    count=int(re.search(r'dcl_temps (\d+)',text)[1]);n=len(water)
    if water.shape!=(131072,4):raise ValueError('WATER_EXTENT')
    r={f'r{i}':np.zeros((n,4),dtype='<u4') for i in range(count)}
    r['vThreadID']=np.column_stack((np.arange(n,dtype='<u4')%512,np.arange(n,dtype='<u4')//512,np.zeros(n,dtype='<u4'),np.zeros(n,dtype='<u4')))
    result=None;observations={};temps={}
    def operand(source):
        negative=source.startswith('-');source=source.lstrip('-')
        if source.startswith('l('):
            values=[int(x.strip(),16) for x in source[2:-1].split(',')]
            value=np.broadcast_to(np.array(values*4 if len(values)==1 else values,dtype='<u4'),(n,4))
        else:
            m=re.fullmatch(r'(r\d+|vThreadID|cb0\[\d+\])(?:\.([xyzw]{1,4}))?',source)
            if not m:raise ValueError('OPERAND:'+source)
            base,swizzle=m.groups();swizzle=swizzle or LANES
            value=np.broadcast_to(constants[int(base[4:-1])],(n,4)) if base.startswith('cb0[') else r[base]
            swizzle=swizzle*4 if len(swizzle)==1 else swizzle
            value=value[:,[LANES.index(c) for c in swizzle]]
        return (-value.view('<f4')).view('<u4') if negative else value
    for number,instruction in re.findall(r'^\s*(\d+):\s+([^\r\n]+)',text,re.M):
        number=int(number)
        m=re.fullmatch(r'(ld_structured_indexable\(structured_buffer, stride=16\)\(mixed,mixed,mixed,mixed\)|\S+)\s*(.*)',instruction.strip())
        op,tail=m.groups();args=split_args(tail) if tail else []
        if op=='ret':continue
        if op=='store_structured':
            if args[0]!='u0.xyzw' or args[2]!='l(0x00000000)':raise ValueError('STORE_LAYOUT')
            index=operand(args[1])[:,0];value=operand(args[3]);result=np.empty_like(water);result[index]=value;continue
        reg,mask=destination(args[0]);positions=[LANES.index(c) for c in mask]
        if op.startswith('ld_structured'):
            if not args[3].startswith('u0.'):raise ValueError('AUXILIARY_UNSUPPORTED')
            index=operand(args[1])[:,0];offset=int(args[2][2:-1],16)//4;swizzle=args[3].split('.')[1]
            value=np.zeros((n,4),dtype='<u4')
            for p in positions:value[:,p]=water[index,offset+LANES.index(swizzle[p])]
        else:
            u=[operand(s) for s in args[1:]];f=[a.view('<f4') for a in u];value=None;fv=None
            if op=='mov':value=u[0]
            elif op=='movc':value=np.where(u[0]!=0,u[1],u[2])
            elif op in ['iadd','imad','and','or','ushr','ishl']:
                value={'iadd':lambda:u[0]+u[1],'imad':lambda:u[0]*u[1]+u[2],'and':lambda:u[0]&u[1],'or':lambda:u[0]|u[1],'ushr':lambda:u[0]>>(u[1]&31),'ishl':lambda:u[0]<<(u[1]&31)}[op]()
            elif op in ['imin','imax']:
                value=(np.minimum if op=='imin' else np.maximum)(u[0].view('<i4'),u[1].view('<i4')).view('<u4')
            elif op in ['ge','lt','ige']:
                compare=(u[0].view('<i4')>=u[1].view('<i4')) if op=='ige' else (f[0]>=f[1] if op=='ge' else f[0]<f[1]);value=np.where(compare,np.uint32(0xffffffff),np.uint32(0))
            elif op in ['bfi','ubfe']:
                width=u[0]&31;offset=u[1]&31;bits=(np.uint32(1)<<width)-np.uint32(1)
                value=(((u[2]&bits)<<offset)|(u[3]&~(bits<<offset))) if op=='bfi' else ((u[2]>>offset)&bits)
            elif op in ['itof','utof']:fv=(u[0].view('<i4') if op=='itof' else u[0]).astype('<f4')
            elif op in ['ftoi','ftou']:value=f[0].astype('<i4' if op=='ftoi' else '<u4').view('<u4')
            elif op in ['add','mul','div','div_sat','mul_sat']:
                if op=='add':fv=f[0]+f[1]
                elif op.startswith('mul'):fv=f[0]*f[1]
                elif division=='rcp_mul':fv=f[0]*np.float32(np.float32(1)/f[1])
                else:fv=f[0]/f[1]
                if op.endswith('_sat'):fv=np.clip(fv,np.float32(0),np.float32(1))
            elif op=='mad':
                fv=fma32(*f)
                if uniform_fold=='advection_dt' and number==16:
                    factor=np.float32(constants.view('<f4')[158,2]*constants.view('<f4')[157,2]);fv=fma32(-temps[9].view('<f4'),factor,f[2])
            elif op in ['min','max']:fv=(np.minimum if op=='min' else np.maximum)(*f)
            elif op=='rsq':fv=np.float32(1)/np.sqrt(f[0])
            elif op=='sqrt':fv=np.sqrt(f[0])
            elif op=='round_ni':fv=np.floor(f[0])
            elif op=='frc':fv=f[0]-np.floor(f[0])
            elif op=='exp':fv=np.exp2(f[0])
            elif op in ['dp2','dp3']:
                products=f[0]*f[1];summed=products[:,0]+products[:,1]
                if op=='dp3':summed=summed+products[:,2]
                fv=np.broadcast_to(summed[:,None],(n,4))
            else:raise ValueError('CPU_OPCODE_NOT_MODELED:'+op)
            if fv is not None:value=np.asarray(fv,dtype='<f4').view('<u4')
        r[reg][:,positions]=value[:,positions];temps[number]=value.copy() if number==9 else None
        if number in captures:observations[number]={k:v.copy() for k,v in r.items() if k!='vThreadID'}
    if result is None:raise ValueError('NO_OUTPUT_STORE')
    return result,observations


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['asm','input','constants','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--capture',default='');ap.add_argument('--division',choices=['native','rcp_mul'],default='rcp_mul');ap.add_argument('--uniform-fold',choices=['none','advection_dt'],default='none')
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    with np.errstate(all='ignore'):
        result,captures=execute(args.asm.read_text(),np.fromfile(args.input,dtype='<u4').reshape(-1,4),np.fromfile(args.constants,dtype='<u4').reshape(-1,4),[int(x) for x in args.capture.split(',') if x],args.division,args.uniform_fold)
    result.tofile(out/'cpu_output.bin')
    for i,regs in captures.items():
        for reg,value in regs.items():value.tofile(out/f'i{i}_{reg}.bin')
    for name in ['dxbc_numpy_probe.py','lower_dxbc_glsl.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    report=dict(operation_status='complete',verification_status='not_evaluated',scope='CPU float expression diagnostic only, not GPU reference or gate',
        asm=identity(args.asm),input=identity(args.input),constants=identity(args.constants),division=args.division,uniform_fold=args.uniform_fold,
        artifacts=[identity(p) for p in out.iterdir() if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(dict(operation='complete',captures=len(captures))))


if __name__=='__main__':main()
