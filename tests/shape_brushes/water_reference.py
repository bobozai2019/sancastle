"""Independent float64 raw-state water conservation and mixed-bed audit."""
import argparse
import json
import math
from pathlib import Path
import numpy as np
from shovel_reference import raw

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    source = args.evidence or args.output.parent/'water_gpu/water_cases.json'
    checks = []
    def check(name, passed, detail=None):
        checks.append(dict(name=name, pass_=bool(passed), detail=detail))
    for case in json.loads(source.read_text(encoding='utf-8')):
        name, before, after, result = (case[k] for k in ['name','before','after','result'])
        if result['status'] == 3:
            check(name+'_atomic', all(before['fields'][k]['sha256']==after['fields'][k]['sha256'] for k in before['fields']))
            continue
        old, new = raw(before,'water'), raw(after,'water')
        sand_delta = raw(after,'sand')-raw(before,'sand')
        error = math.fsum(((new-old)*.015625).flat)
        check(name+'_water_conserved',abs(error)<=result['eps_water_m3'],error)
        changed=new!=old
        quantum=float(np.sum(2*np.spacing(np.maximum(abs(old[changed]),abs(new[changed])).astype(np.float32)).astype(np.float64)*.015625))
        # GPU subtracts float32 depths; raw audit subtracts the exact float32
        # values in float64. Compare using their independently computed Q.
        check(name+'_receipt_error',abs(error-result['water_error_m3'])<=max(1e-8,quantum),{'raw_error':error,'changed_quantum':quantum})
        check(name+'_finite_nonnegative',np.isfinite(new).all() and (new>=0).all())
        check(name+'_sediment_conserved',abs(math.fsum(((raw(after,'sediment')-raw(before,'sediment'))*.015625).flat))<=1e-7)
        check(name+'_rock_immutable',before['fields']['rock']['sha256']==after['fields']['rock']['sha256'])
        check(name+'_bed_raised',(sand_delta>0).any())
        if case['command']['brush_id']=='shovel_v1':
            check(name+'_bed_lowered',(sand_delta<0).any())
            check(name+'_sand_conserved',abs(math.fsum((sand_delta*.015625).flat))<=result['eps_sand_m3'])
        if case['command']['speed_m_s']==0:
            for field in ['momentum_x','momentum_z']:
                q_before,q_after=raw(before,field),raw(after,field)
                q_error=math.fsum(((q_after-q_before)*.015625).flat)
                q_quantum=float(np.sum(2*np.spacing(np.maximum(abs(q_before),abs(q_after)).astype(np.float32)).astype(np.float64)*.015625))
                check(name+'_'+field+'_conserved',abs(q_error)<=max(1e-8,q_quantum),q_error)
            check(name+'_no_velocity_impulse',result['impulse_x_m4_s']==0 and result['impulse_z_m4_s']==0)
        else:
            qx,qz=raw(after,'momentum_x'),raw(after,'momentum_z')
            magnitude = np.hypot(qx,qz)
            check(name+'_velocity_injected',(magnitude>0).any())
            check(name+'_speed_cap',np.all(magnitude<=4*new+1e-7))
            axis=(np.arange(256)+.5-128)*.125
            x,z=np.meshgrid(axis,axis)
            if case['command']['brush_id']=='castle_v1':
                # These velocity samples are yaw=0, scale=1; evaluate the
                # template on adjacent physical centers independently.
                template=np.fromfile(Path(__file__).resolve().parents[2]/'assets/brushes/castle/four_towers_v1.rgba32f',dtype='<f4').reshape(65,65,4)
                def height(px,pz):
                    ix=np.rint((px+2)/.0625).astype(int);iz=np.rint((pz+2)/.0625).astype(int)
                    valid=(ix>=0)&(ix<65)&(iz>=0)&(iz<65)
                    return np.where(valid,template[np.clip(iz,0,64),np.clip(ix,0,64),0],0).astype(np.float64)
                dx=height(x-.125,z)-height(x+.125,z);dz=height(x,z-.125)-height(x,z+.125)
            else:
                dx=x-np.clip(x,-.5,.5);dz=z
            norm=np.hypot(dx,dz);dx=np.divide(dx,norm,out=np.zeros_like(dx),where=norm>0);dz=np.divide(dz,norm,out=np.zeros_like(dz),where=norm>0)
            active=magnitude>0
            check(name+'_outward_direction',np.all((qx*dx+qz*dz)[active]>0) and np.all(abs(qx*dz-qz*dx)[active]<=32*(2**-24)*magnitude[active]))
            check(name+'_only_raised_wet_cells',np.all((sand_delta>0)[active] & (new>.001)[active]))
            for field,component,key in [('momentum_x',qx,'impulse_x_m4_s'),('momentum_z',qz,'impulse_z_m4_s')]:
                oldq=raw(before,field);delta=component-oldq
                impulse=math.fsum(delta.flat)*.015625
                Q=math.fsum((2*np.spacing(np.maximum(abs(component),abs(oldq)).astype('<f4')).astype(np.float64)).flat)*.015625
                check(name+'_'+key+'_receipt',abs(impulse-result[key])<=max(1e-8,Q),impulse)
        check(name+'_resource_count',case['statistics']['rid_count']==69)
        if name=='wall_disconnected':
            axis=(np.arange(256)+.5-128)*.125
            x,z=np.meshgrid(axis,axis)
            remote=(x-8)**2+z*z<1
            check(name+'_remote_unchanged',np.array_equal(new[remote],old[remote]))
        if name=='wall_capacity':
            demand=math.fsum(np.minimum(old,np.maximum(sand_delta,0)).flat)*.015625
            check(name+'_retained_demand',result['capacity_status']==1 and abs(result['retained_water_m3']-demand)<=result['eps_water_m3'],demand)
            check(name+'_no_receiver_no_water_loss',result['displaced_water_m3']==0 and np.array_equal(new,old))
    report = {'pass':all(c['pass_'] for c in checks),'checks':[{('pass' if k=='pass_' else k):v for k,v in c.items()} for c in checks]}
    (args.output/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('WATER_REFERENCE',report['pass'],len(checks))
    raise SystemExit(0 if report['pass'] else 1)

if __name__=='__main__':main()
