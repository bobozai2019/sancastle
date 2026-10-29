"""Independent float64 capsule masks, capacity water filling and raw accounting."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from wall_reference import capsule_distance

U = 2**-24
A = .125**2


def raw(record, name, channels=1, dtype='<f4'):
    entry = record['fields'][name]
    data = Path(entry['path']).read_bytes()
    assert len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256']
    return np.frombuffer(data, dtype=dtype).astype(np.float64).reshape(256, 256, channels).squeeze()


def fill(capacity, weight, requested):
    """Double water-filling root, separate from GPU float32 + residual repair."""
    result = np.zeros_like(capacity)
    mask = weight > 0
    requested = min(requested, math.fsum(capacity[mask]))
    if requested <= 0:return result
    low, high = 0., 1.
    def total(multiplier):return math.fsum(np.minimum(capacity[mask], multiplier*weight[mask]))
    while total(high) < requested:high *= 2
    for _ in range(100):
        middle = (low+high)/2
        if total(middle) < requested:low = middle
        else:high = middle
    result[mask] = np.minimum(capacity[mask], high*weight[mask])
    return result


def wire_budget(value):
    rounded = np.float32(value)
    if rounded > value:rounded = np.nextafter(rounded, np.float32(-math.inf))
    return float(rounded)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args();args.output.mkdir(parents=True, exist_ok=True)
    source = args.evidence or args.output.parent/'shovel_gpu/shovel_cases.json'
    checks, metrics = [], []
    def check(name, value, detail=None):checks.append({'name':name, 'pass':bool(value), 'detail':detail})
    axis = (np.arange(256)+.5-128)*.125;x,z = np.meshgrid(axis,axis)
    for case in json.loads(source.read_text(encoding='utf-8')):
        name, before, after, cmd, receipt = case['name'], case['before'], case['after'], case['command'], case['result']
        old, new, rock = raw(before,'sand'), raw(after,'sand'), raw(before,'rock')
        check(name+'_rock', np.array_equal(rock,raw(after,'rock')))
        check(name+'_ledger', all(case['before_metadata'][key] == case['after_metadata'][key] for key in ['source','sink','inventory']))
        check(name+'_no_external_source',receipt['external_source_delta_m3']==0 and receipt['external_sink_delta_m3']==0)
        if receipt['status'] != 1:
            check(name+'_all_raw_atomic',all(before['fields'][key]['sha256']==after['fields'][key]['sha256'] for key in before['fields']))
            continue
        start, finish = case['start'], case['end']
        distance = capsule_distance(x,z,start,finish)
        radius, depth, shoulder = cmd['trench_width_m']/2,cmd['depth_m'],cmd['shoulder_width_m']
        donor = distance < radius
        side = (finish[0]-start[0])*(z-start[1])-(finish[1]-start[1])*(x-start[0])
        obstacle = raw(before,'obstacle',dtype='u1') > 0
        left = (distance>=radius)&(distance<radius+shoulder)&(side>=0)&~obstacle
        right = (distance>=radius)&(distance<radius+shoulder)&(side<0)&~obstacle
        weight = np.where(left|right,np.maximum(0,np.sin(math.pi*(distance-radius)/shoulder)),0)
        base = (old.astype('<f4')+rock.astype('<f4')).astype(np.float64)
        target = np.maximum(rock,base-depth*np.clip(1-(distance/radius)**2,0,1))
        potential = np.where(donor,np.maximum(0,old-np.maximum(0,target-rock)),0)
        capacity = np.maximum(0,base+.5-rock-old)
        capacity_left = np.where(left & (weight>0),capacity,0)
        capacity_right = np.where(right & (weight>0),capacity,0)
        potential_sum = math.fsum(potential.ravel())
        request = wire_budget(cmd['transfer_budget_m3'])/A
        cut = min(potential_sum,request,2*math.fsum(capacity_left.ravel()),2*math.fsum(capacity_right.ravel()))
        cut_field = potential*(cut/potential_sum if potential_sum else 0)
        allocation_left = fill(capacity_left.ravel(),np.where(left,weight,0).ravel(),cut/2).reshape(256,256)
        allocation_right = fill(capacity_right.ravel(),np.where(right,weight,0).ravel(),cut/2).reshape(256,256)
        expected = old-cut_field+allocation_left+allocation_right
        # Same capsule arithmetic sensitivity allowance used by the wall oracle,
        # with trench max slope 2*depth/radius. This is geometry, not mass budget.
        bound = 8*U*(np.maximum(1,np.abs(old))+np.abs(rock)+depth)+32*U*16*(2*depth/radius)
        check(name+'_double_geometry',np.all(np.abs(new-expected)<=bound),{'max_error_m':float(np.abs(new-expected).max()),'max_bound_m':float(bound.max())})
        check(name+'_outside_unchanged',np.array_equal(new[~(donor|left|right)],old[~(donor|left|right)]))
        change = new-old
        check(name+'_donor_receiver_disjoint',not np.any(donor & (left|right)) and np.all(change[donor]<=0) and np.all(change[left|right]>=0))
        check(name+'_nonnegative_sand',np.isfinite(new).all() and np.all(new>=0))
        removed = math.fsum(-change[donor])*A
        received_left,received_right = math.fsum(change[left])*A,math.fsum(change[right])*A
        net = math.fsum(change.ravel())*A
        touched = donor | ((left|right)&(weight>0))
        ulps = np.spacing(np.maximum(np.abs(old),np.abs(new)).astype('<f4')).astype(np.float64)
        quantization = math.fsum((2*ulps[touched]).ravel())*A
        absolute_sum = math.fsum(np.abs(change).ravel())*A
        reduction = max(1e-8,(8*U+2*(int(touched.sum())+256)*U*U)*absolute_sum)
        oracle_eps = max(1e-7,quantization+reduction)
        check(name+'_independent_budget',abs(receipt['eps_sand_m3']-oracle_eps)<=16*U*oracle_eps and abs(receipt['eps_transfer_m3']-2*oracle_eps)<=32*U*oracle_eps,{'Q':quantization,'R':reduction,'n':int(touched.sum()),'oracle_E':oracle_eps,'receipt_E':receipt['eps_sand_m3']})
        eps = 2*oracle_eps
        check(name+'_actual_cut_receivers',abs(removed-received_left-received_right)<=eps and abs(received_left-received_right)<=eps and abs(net)<=eps,{'removed':removed,'left':received_left,'right':received_right,'net':net,'eps':eps})
        check(name+'_receipt_raw_amounts',abs(removed-receipt['removed_m3'])<=receipt['eps_sand_m3'] and abs(received_left-receipt['left_received_m3'])<=receipt['eps_sand_m3'] and abs(received_right-receipt['right_received_m3'])<=receipt['eps_sand_m3'])
        check(name+'_finite_budget',removed<=wire_budget(cmd['transfer_budget_m3'])+receipt['eps_sand_m3'])
        check(name+'_published',np.array_equal(new,raw(after,'published_sand')))
        check(name+'_sand_dual',after['fields']['sand']['sha256']==after['fields']['spare_sand']['sha256'])
        old_tag,tag = raw(before,'mold_support_0',2),raw(after,'mold_support_0',2)
        lost = np.minimum(old_tag[:,:,0],np.maximum(-change,0))
        fraction = math.fsum(lost.ravel())/math.fsum(np.maximum(-change,0).ravel()) if removed>0 else 0
        expected_tag = np.maximum(old_tag[:,:,0]-np.maximum(-change,0),0)+np.maximum(change,0)*fraction
        material_bound = 16*U*(np.maximum(1,np.abs(old_tag[:,:,0]))+np.abs(change))
        check(name+'_tag_mixture',np.all(np.abs(tag[:,:,0]-expected_tag)<=material_bound),{'max_error_m':float(np.abs(tag[:,:,0]-expected_tag).max())})
        check(name+'_tag_reference',np.array_equal(tag[:,:,1],np.where(tag[:,:,0]>0,new,0)))
        check(name+'_tag_legal',np.isfinite(tag).all() and np.all(tag[:,:,0]>=0) and np.all(tag[:,:,0]<=new))
        check(name+'_tag_dual',after['fields']['mold_support_0']['sha256']==after['fields']['mold_support_1']['sha256'])
        old_comp,comp = raw(before,'compaction',dtype='<f2'),raw(after,'compaction',dtype='<f2')
        mean = math.fsum((np.maximum(-change,0)*old_comp).ravel())/math.fsum(np.maximum(-change,0).ravel()) if removed>0 else 0
        expected_comp = np.where(change>0,np.divide(old*old_comp+np.maximum(change,0)*mean,new,out=np.zeros_like(new),where=new>0),old_comp)
        half = expected_comp.astype('<f2')
        half_ulp = np.abs(np.nextafter(half,np.float16(math.inf)).astype(np.float64)-half.astype(np.float64))
        check(name+'_compaction_mixture',np.all(np.abs(comp-expected_comp)<=half_ulp+16*U),{'max_error':float(np.abs(comp-expected_comp).max()),'storage':'R16F one half ULP plus float32 forward arithmetic'})
        check(name+'_tag_amount',abs(math.fsum((tag[:,:,0]-old_tag[:,:,0]).ravel())*A)<=receipt['eps_sand_m3'])
        metrics.append({'name':name,'removed_m3':removed,'left_m3':received_left,'right_m3':received_right,'net_m3':net,'eps_transfer_m3':eps,'max_geometry_error_m':float(np.abs(new-expected).max())})
        expected.astype('<f4').tofile(args.output/(name+'_reference_sand.bin'))
    result={'pass':all(row['pass'] for row in checks),'checks':checks,'metrics':metrics,'scope':'single segment dry candidate; float64 geometry/capacity and actual binary32 mass; no long-run/water/UI claim'}
    (args.output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'pass':result['pass'],'checks':len(checks)}));raise SystemExit(0 if result['pass'] else 1)


if __name__=='__main__':main()
