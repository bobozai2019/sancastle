"""Archive arithmetic expression fits and an independent native refactoring-policy control."""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
from evidence_contract import identity
from dxbc_numpy_probe import fma32


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--root',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    b=args.root.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);dependencies=[]
    def trace(name):
        p=b/name/'trace_audit.json';a=json.loads(p.read_text());dependencies.append(identity(p))
        if a['verification_status']!='passed' or not a['trace_repeats_stable'] or not a['observation_preserves_both_normal_outputs']:raise ValueError('TRACE_NOT_READY')
        row=a['rows'][0];values=[]
        for key in ['native_trace','godot_trace']:
            if identity(row[key]['path'])['sha256']!=row[key]['sha256']:raise ValueError('TRACE_CHANGED')
            values.append(np.fromfile(row[key]['path'],dtype='<u4').reshape(-1,4))
        return values
    old=json.loads((b/'t06_snapshot_reference_pilot_20261025_v1/manifest.json').read_text());strict=json.loads((b/'t06_strict_snapshot_reference_20261025_v1/manifest.json').read_text())
    if old['verification_status']!='passed' or strict['verification_status']!='passed':raise ValueError('REFERENCE_NOT_READY')
    policy=[]
    for r in strict['references']:
        original=next(s for s in old['references'] if s['reference_id']==r['reference_id']);a=r['checks'][0]['after'];c=original['checks'][0]['after']
        for item in [a,c]:
            if identity(item['path'])['sha256']!=item['sha256']:raise ValueError('REFERENCE_CHANGED')
        policy.append(dict(event=r['event_id'],strict_output=a,original_policy_output=c,word_differences=int(np.count_nonzero(np.fromfile(a['path'],dtype='<u4')!=np.fromfile(c['path'],dtype='<u4')))))
    r9,_=trace('t06_register_pair_e1500_i9_20261025_v1');r15,_=trace('t06_register_pair_e1500_i15_r2_20261025_v1');r16,_=trace('t06_register_pair_e1500_i16_20261025_v1')
    ref=next(r for r in old['references'] if r['event_id']==1500);cb=np.fromfile(ref['constants']['path'],dtype='<f4').reshape(-1,4);factor=np.float32(cb[158,2]*cb[157,2])
    adv=[]
    for lane,other in [(1,2),(2,3)]:
        model=fma32(-r9[:,lane].view('<f4'),factor,r15[:,other].view('<f4'))
        adv.append(dict(lane='xyzw'[lane],nominal_register_model_mismatches=int(np.count_nonzero(model.view('<u4')!=r16[:,lane]))))
    drag,drag_godot=trace('t06_register_pair_e1490_drag_20261025_v1');dot,dot_godot=trace('t06_register_pair_e1490_dp2_20261025_v1');norm,norm_godot=trace('t06_register_pair_e1490_norm_20261025_v1')
    cpu=b/'t06_cpu_velocity_20261025_v1';cpu_manifest=json.loads((cpu/'manifest.json').read_text());dependencies.append(identity(cpu/'manifest.json'))
    for a in cpu_manifest['artifacts']:
        if identity(a['path'])['sha256']!=a['sha256']:raise ValueError('CPU_PROBE_ARTIFACT_CHANGED')
    depth=np.fromfile(cpu/'i116_r0.bin',dtype='<f4').reshape(-1,4)[:,2];velocity=drag[:,1].view('<f4');dt=np.float32(cb[157,2])
    drag_models={'literal_mul_then_fma':fma32(-np.float32(depth*velocity),dt,velocity),'depth_dt_then_fma':fma32(velocity,-np.float32(depth*dt),velocity),'one_minus_then_mul':np.float32(velocity*fma32(-depth,dt,np.float32(1)))}
    f=dot.view('<f4');x,y=f[:,0],f[:,1]
    dot_models={'separate':np.float32(np.float32(x*x)+np.float32(y*y)),'fma_x':fma32(x,x,np.float32(y*y)),'fma_y':fma32(y,y,np.float32(x*x))}
    report=dict(operation_status='complete',verification_status='not_evaluated',scope='Finite arithmetic-model fits and native flag counterfactual, not a complete machine-code trace or G02/G5 acceptance.',
        dependency_reports=dependencies,refactoring_policy_control=policy,advection_combined_scale=dict(value=float(factor),word=hex(int(factor.view('<u4'))),expression='fma(-pre_scale_division, float32(scale*dt), uv)',fits=adv),
        velocity_drag=dict(trace_lane_differences=np.count_nonzero(drag!=drag_godot,axis=0).tolist(),source='Observed stage116 velocity; depth from CPU expression probe whose full output is not accepted as GPU reference',models={name:int(np.count_nonzero(value.view('<u4')!=drag[:,2])) for name,value in drag_models.items()}),
        velocity_dot=dict(joint_input_differences=np.count_nonzero(dot[:,:2]!=dot_godot[:,:2],axis=0).tolist(),models={name:int(np.count_nonzero(value.view('<u4')!=dot[:,2])) for name,value in dot_models.items()},same_magnitude_different_rsq=int(np.count_nonzero((norm[:,0]==norm_godot[:,0])&(norm[:,1]!=norm_godot[:,1])))),
        interpretation='Nominal register copies may be recomputed or bypassed by the native compiler under refactoringAllowed. Same copied inputs do not prove those exact temporaries feed a physical MAD. Clearing the permission changes native output and supplies a separate causal control. Expression fits are scoped models, not recovered HLSL or proof of a particular machine instruction.',
        primary_sources=['https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dcl-globalflags','https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/mad'],
        unknowns=['Driver machine instructions and optimization across unobserved inputs','Exact hardware rsq approximation','Unmodified original in-place read stream and all possible schedules'])
    (out/'models.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for name in ['verify_reassociation_models.py','dxbc_numpy_probe.py','lower_dxbc_glsl.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='not_evaluated',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(policy_word_differences=[p['word_differences'] for p in policy],advection=adv,velocity_drag=report['velocity_drag']['models'],velocity_dot=report['velocity_dot'])))


if __name__=='__main__':main()
