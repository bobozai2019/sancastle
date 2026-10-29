"""CPU arithmetic hypotheses for jointly observed GPU operands; never acceptance oracle."""
import argparse
import ctypes
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['advection','velocity','build','output']:ap.add_argument('--'+name,type=Path,required=True)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    root=Path(__file__).resolve().parents[3]
    def read(directory):
        audit=json.loads((directory/'trace_audit.json').read_text())
        if audit['verification_status']!='passed' or not audit['observation_preserves_both_normal_outputs'] or not audit['trace_repeats_stable']:raise ValueError('TRACE_NOT_READY')
        row=audit['rows'][0]
        for key in ['native_trace','godot_trace']:
            if identity(row[key]['path'])['sha256']!=row[key]['sha256']:raise ValueError('TRACE_BYTES_CHANGED')
        return audit,np.fromfile(row['native_trace']['path'],dtype='<u4').reshape(-1,4),np.fromfile(row['godot_trace']['path'],dtype='<u4').reshape(-1,4)
    aa,n,g=read(args.advection);va,v,w=read(args.velocity)
    fmaf=ctypes.CDLL('ucrtbase.dll').fmaf;fmaf.argtypes=[ctypes.c_float]*3;fmaf.restype=ctypes.c_float
    if fmaf(1,1,1)!=2:raise ValueError('CPU_FMA_SMOKE')
    ar=json.loads(Path(aa['request']['path']).read_text());dt=np.fromfile(ar['reference']['constants']['path'],dtype='<f4').reshape(-1,4)[157,2]
    nf=n.view('<f4');fma=np.array([fmaf(-a,dt,c) for a,c in zip(nf[:,0],nf[:,1])],dtype='<f4').view('<u4')
    separate=np.float32(np.float32(-nf[:,0]*dt)+nf[:,1]).view('<u4')
    def counts(target,models):return {name:int(np.count_nonzero(target!=value)) for name,value in models.items()}
    i=94*512+328
    adv=dict(input_lane_differences=np.count_nonzero(n[:,:2]!=g[:,:2],axis=0).tolist(),native_mad_model_mismatches=counts(n[:,2],dict(cpu_fmaf=fma,separate_mul_add=separate)),
        native_matches_neither=int(np.count_nonzero((n[:,2]!=fma)&(n[:,2]!=separate))),
        example=dict(coordinate=[328,94],native_joint_words=[hex(int(x)) for x in n[i]],godot_joint_words=[hex(int(x)) for x in g[i]],cpu_fma_word=hex(int(fma[i])),cpu_separate_word=hex(int(separate[i]))))
    vf=v.view('<f4');direct=np.float32(vf[:,0]/vf[:,1]).view('<u4');reciprocal=np.float32(vf[:,0]*np.float32(np.float32(1)/vf[:,1])).view('<u4')
    vel=dict(lane_differences=np.count_nonzero(v!=w,axis=0).tolist(),native_div_model_mismatches=counts(v[:,2],dict(correctly_rounded_division=direct,rounded_reciprocal_then_multiply=reciprocal)),
        example=dict(coordinate=[248,0],native_joint_words=[hex(int(x)) for x in v[248]],godot_joint_words=[hex(int(x)) for x in w[248]]))
    # Actual executor validation before GPU creation: wrong layout and missing dependency.
    request=json.loads(Path(va['request']['path']).read_text());ref=request['reference'];exe=args.build/'water_trace_reference.exe'
    command=[str(exe),'--program',ref['adapted_program']['path'],'--snapshot',ref['snapshot']['path'],'--input',ref['output_seed']['path'],'--constants',ref['constants']['path'],'--output',str(out/'should_not_exist')]
    negatives=[]
    for name,cmd,expected in [('unobserved_one_uav_layout',command,b'unsupported_uav_sampler_or_counter'),('missing_snapshot',[x for j,x in enumerate(command) if j not in [3,4]],b'ARGUMENT_MISSING:--snapshot')]:
        result=subprocess.run(cmd,capture_output=True);(out/(name+'_stderr.bin')).write_bytes(result.stderr);(out/(name+'_stdout.bin')).write_bytes(result.stdout)
        negatives.append(dict(name=name,command=cmd,exit_code=result.returncode,expected_rejection=expected.decode(),passed=result.returncode!=0 and expected in result.stderr and not (out/'should_not_exist').exists()))
    # Explicitly audit raw opcode controls instead of inferring missing flags from printed ASM.
    from make_snapshot_dxbc import sections
    from collections import Counter
    base=root/'docs/competitor/evidence/water_solver_reconstruction/t06_exact_programs_20261025_v1';flags=[]
    for e in [1484,1490,1495,1500,1537,1543]:
        _,_,_,_,code,_,numbered=sections((base/f'e{e}.dxbc').read_bytes(),(base/f'e{e}_exact.asm').read_text())
        c=Counter((text.split()[0],hex(row[0]&0x00fff800)) for row,(_,text) in zip(code,numbered))
        flags.append(dict(event=e,nonzero_controls=[dict(opcode=op,control=control,count=count) for (op,control),count in c.items() if control!='0x0']))
    report=dict(operation_status='complete',verification_status='passed' if all(n['passed'] for n in negatives) else 'failed',
        scope='Finite joint-input arithmetic diagnostics, not a universal native compiler model or tolerance/acceptance change',
        advection_source=identity(args.advection/'trace_audit.json'),velocity_source=identity(args.velocity/'trace_audit.json'),
        cpu_fma_library=identity('C:/Windows/System32/ucrtbase.dll'),advection=adv,velocity=vel,negative_cases=negatives,opcode_control_audit=flags,
        primary_sources=['https://learn.microsoft.com/en-us/windows/win32/direct3d11/floating-point-rules','https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/mad'],
        unknowns=['Why the observed native MAD is not uniformly CPU IEEE fmaf or separate round-to-nearest on all cells','Compiler duplication/reassociation and observation perturbation beyond unchanged final bytes','Other fixtures and unmodified original in-place schedules'])
    (out/'models.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for name in ['analyze_register_models.py','make_snapshot_dxbc.py','probe_dxbc_rebuild.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],advection=adv,velocity=vel,negative_passes=sum(n['passed'] for n in negatives))))
    raise SystemExit(report['verification_status']!='passed')


if __name__=='__main__':main()
