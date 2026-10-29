"""Independent binary32-state audit of sampled mixed/overlapping shovel paths."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from shovel_reference import raw,fill,wire_budget,U,A
from wall_reference import capsule_distance

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--evidence',type=Path)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    checks=[];metrics=[]
    def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
    axis=(np.arange(256)+.5-128)*.125;x,z=np.meshgrid(axis,axis)
    source=args.evidence or args.output.parent/'shovel_path/shovel_paths.json'
    cases=json.loads(source.read_text(encoding='utf-8'))
    for case in cases:
        rock=raw(case['initial'],'rock')
        check(case['name']+'_rock_immutable',case['initial']['fields']['rock']['sha256']==case['final']['fields']['rock']['sha256'])
        count=0
        for phase_index,phase in enumerate(case['phases']):
            baseline=case['fresh_initial'] if phase_index==2 else case['initial']
            bed=(rock+raw(baseline,'sand')).astype('<f4').astype(np.float64)
            for index,step in enumerate(phase['steps']):
                name=f"{case['name']}_{phase_index}_{index}";before,after,cmd,r=(step[k] for k in ['before','after','command','result'])
                old,new=raw(before,'sand'),raw(after,'sand');change=new-old
                check(name+'_no_external',r['external_source_delta_m3']==0 and r['external_sink_delta_m3']==0)
                if r['status']==2:
                    check(name+'_no_change_raw',all(before['fields'][key]['sha256']==after['fields'][key]['sha256'] for key in before['fields']))
                    continue
                check(name+'_success',r['status']==1)
                distance=capsule_distance(x,z,step['start'],step['end']);radius=cmd['trench_width_m']/2;depth=cmd['depth_m'];shoulder=cmd['shoulder_width_m']
                cv=raw(before,'coverage',2);donor=distance<radius
                direction=np.array(step['end'])-np.array(step['start']);direction/=np.linalg.norm(direction)
                # Orthogonal signed distance is independent of the closest-point parameter.
                side=(x-step['start'][0])*(-direction[1])+(z-step['start'][1])*direction[0]
                receiver=(distance>=radius)&(distance<radius+shoulder)&(cv[:,:,1]==0)
                left,right=receiver&(side>=0),receiver&(side<0)
                weight=np.where(receiver,np.maximum(0,np.sin(math.pi*(distance-radius)/shoulder)),0)
                profile=np.maximum(0,1-(distance/radius)**2)
                target=np.maximum(rock,bed-depth*profile)
                history=cv[:,:,1]>0
                target=np.where(history,np.maximum(rock,np.where(profile<=cv[:,:,1],cv[:,:,0],np.minimum(target,cv[:,:,0]))),target)
                potential=np.where(donor,np.maximum(0,old-np.maximum(0,target-rock)),0)
                capacity=np.maximum(0,bed+.5-rock-old)
                potential_sum=math.fsum(potential.flat)
                allowed=min(potential_sum,wire_budget(cmd['transfer_budget_m3'])/A,2*math.fsum(capacity[left]),2*math.fsum(capacity[right]))
                expected=old-potential*(allowed/potential_sum if potential_sum else 0)
                expected+=fill(np.where(left,capacity,0).ravel(),np.where(left,weight,0).ravel(),allowed/2).reshape(256,256)
                expected+=fill(np.where(right,capacity,0).ravel(),np.where(right,weight,0).ravel(),allowed/2).reshape(256,256)
                bound=8*U*(np.maximum(1,abs(old))+abs(rock)+depth)+32*U*16*(2*depth/radius)
                check(name+'_double_geometry',np.all(abs(new-expected)<=bound),float(np.max(abs(new-expected))))
                touched=donor|(receiver&(weight>0))
                check(name+'_outside_unchanged',np.array_equal(old[~touched],new[~touched]))
                Q=math.fsum((2*np.spacing(np.maximum(abs(old),abs(new)).astype('<f4')).astype(np.float64)[touched]).flat)*A
                absolute=math.fsum(abs(change).flat)*A
                E=max(1e-7,Q+max(1e-8,(8*U+2*(int(touched.sum())+256)*U*U)*absolute))
                check(name+'_frozen_budget',abs(r['eps_sand_m3']-E)<=16*U*E and abs(r['eps_transfer_m3']-2*E)<=32*U*E,{'Q':Q,'E':E,'receipt_E':r['eps_sand_m3']})
                removed=math.fsum(np.maximum(-change,0).flat)*A;got_left=math.fsum(change[left])*A;got_right=math.fsum(change[right])*A
                check(name+'_raw_mass',abs(math.fsum(change.flat)*A)<=2*E and abs(removed-got_left-got_right)<=2*E and abs(got_left-got_right)<=2*E)
                check(name+'_receipt_amounts',abs(removed-r['removed_m3'])<=E and abs(got_left-r['left_received_m3'])<=E and abs(got_right-r['right_received_m3'])<=E)
                check(name+'_finite_permission',removed<=wire_budget(cmd['transfer_budget_m3'])+E)
                check(name+'_bed_valid',np.isfinite(new).all() and (new>=0).all())
                old_tag,tag=raw(before,'mold_support_0',2),raw(after,'mold_support_0',2)
                cut=np.maximum(-change,0);added=np.maximum(change,0);total_cut=math.fsum(cut.flat)
                fraction=math.fsum(np.minimum(old_tag[:,:,0],cut).flat)/total_cut if total_cut else 0
                expected_tag=np.maximum(old_tag[:,:,0]-cut,0)+added*fraction
                check(name+'_tag_mixture',np.all(abs(tag[:,:,0]-expected_tag)<=16*U*(np.maximum(1,abs(old_tag[:,:,0]))+abs(change))))
                check(name+'_tag_legal',np.isfinite(tag).all() and (tag[:,:,0]>=0).all() and (tag[:,:,0]<=new).all() and np.array_equal(tag[:,:,1],np.where(tag[:,:,0]>0,new,0)))
                old_comp,comp=raw(before,'compaction',dtype='<f2'),raw(after,'compaction',dtype='<f2')
                mean=math.fsum((cut*old_comp).flat)/total_cut if total_cut else 0
                expected_comp=np.where(added>0,(old*old_comp+added*mean)/new,old_comp).astype('<f2')
                half_ulp=abs(np.nextafter(expected_comp,np.float16(math.inf)).astype(np.float64)-expected_comp.astype(np.float64))
                check(name+'_compaction_mixture',np.all(abs(comp-expected_comp.astype(np.float64))<=half_ulp))
                water_error=math.fsum((raw(after,'water')-raw(before,'water')).flat)*A
                check(name+'_water_conserved',abs(water_error)<=max(1e-7,r['eps_water_m3']),water_error)
                count+=1
        metrics.append({'case':case['name'],'successful_segments':count,'total_segments':sum(len(p['steps']) for p in case['phases'])})
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'metrics':metrics,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'per-segment complete input raw state, float64 geometric allocation and frozen mass budget; no cost/long-run verdict'}
    (args.output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({'pass':result['pass'],'checks':len(checks),'metrics':metrics}));raise SystemExit(0 if result['pass'] else 1)

if __name__=='__main__':main()
