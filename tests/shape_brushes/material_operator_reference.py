"""Independent shared-edge and suspended transport reference for one dispatch."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from retention_reference import raw


U=2**-24
GAMMA128=128*U/(1-128*U)

def field(sample,name,channels=1):
    if channels==1:return raw(sample,name)
    f=sample['fields'][name];data=Path(f['path']).read_bytes()
    assert len(data)==f['bytes'] and hashlib.sha256(data).hexdigest()==f['sha256']
    return np.frombuffer(data,dtype='<f4').astype(np.float64).reshape(256,256,channels)

def smooth(a,b,value):
    t=np.clip((value-a)/(b-a),0,1);return t*t*(3-2*t)

def slope_reference(sample,after,p):
    sand=raw(sample,'sand');rock=raw(sample,'rock');old=field(sample,'mold_support_0',2)
    tag=np.clip(old[:,:,0]-np.maximum(old[:,:,1]-sand,0),0,sand)
    wet=raw(after,'wetness');compact=raw(after,'compaction')
    f=sample['fields']['obstacle'];obstacle=np.frombuffer(Path(f['path']).read_bytes(),dtype='u1').reshape(256,256)>0
    next_sand=sand.copy();next_tag=tag.copy();bed=rock+sand
    # Each undirected edge is evaluated once and booked to both cells.
    for sa,sb in [(np.s_[:,:-1],np.s_[:,1:]),(np.s_[:-1,:],np.s_[1:,:])]:
        donor_a=bed[sa]>=bed[sb]
        ds=np.where(donor_a,sand[sa],sand[sb]);dt=np.where(donor_a,tag[sa],tag[sb])
        dc=np.where(donor_a,compact[sa],compact[sb]);dw=np.where(donor_a,wet[sa],wet[sb])
        tangent=p[3]+(p[4]-p[3])*(wet[sa]+wet[sb])*.5+p[5]*(compact[sa]+compact[sb])*.5
        moisture=.8+.2*smooth(.05,.35,dw)-.6*smooth(.65,1,dw)
        strength=np.clip((dc-.6)/.35,0,1)*moisture
        repose=np.maximum(tangent*p[1],p[6])+p[7]*strength+p[8]*np.clip(dt/p[9],0,1)*strength
        moved=np.minimum(np.maximum(np.abs(bed[sa]-bed[sb])-repose,0)*.5*np.clip(p[2]*p[0],0,1),ds*.25)
        moved=np.where(obstacle[sa]|obstacle[sb],0,moved)
        signed=np.where(donor_a,-moved,moved)
        tag_signed=signed*np.divide(dt,ds,out=np.zeros_like(dt),where=ds>0)
        next_sand[sa]+=signed;next_sand[sb]-=signed
        next_tag[sa]+=tag_signed;next_tag[sb]-=tag_signed
    return np.maximum(next_sand,0),np.clip(next_tag,0,np.maximum(next_sand,0)),tag

def sediment_reference(sample,p):
    before=raw(sample,'spare_water');after=raw(sample,'water');suspended=raw(sample,'spare_sediment')
    sand=raw(sample,'spare_sand');wet=raw(sample,'spare_wetness');compact=raw(sample,'spare_compaction')
    flux=field(sample,'flux',4);out=np.maximum(flux,0)*p[0]/p[1]
    total=out.sum(axis=2);denom=np.maximum(before,total)
    next_suspended=suspended*np.where(before>1e-8,np.maximum(0,1-np.divide(total,denom,out=np.zeros_like(total),where=denom>0)),1)
    transferred=suspended[:,:,None]*np.divide(out,denom[:,:,None],out=np.zeros_like(out),where=denom[:,:,None]>0)
    transferred=np.where(before[:,:,None]>1e-8,transferred,0)
    next_suspended[:,1:]+=transferred[:,:-1,1];next_suspended[:,:-1]+=transferred[:,1:,0]
    next_suspended[1:,:]+=transferred[:-1,:,3];next_suspended[:-1,:]+=transferred[1:,:,2]
    capacity=np.maximum(flux,0).sum(axis=2)/p[1]*after*p[2]/((.7+1.1*compact)*(1+.25*wet))
    eroded=np.minimum(sand,np.maximum(capacity-next_suspended,0)*p[3]*p[0])
    deposited=np.minimum(next_suspended,np.maximum(next_suspended-capacity,0)*p[4]*p[0])
    dry=after<=p[5]
    return np.where(dry,sand+next_suspended,sand-eroded+deposited),np.where(dry,0,next_suspended+eroded-deposited)

def run(output):
    evidence=json.loads((output.parent/'material_operator/operator_evidence.json').read_text());checks=[];metrics={}
    def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
    for case in evidence['cases']:
        name=case['name'];a,b,c=[case[n] for n in ['input','pre_material','output']]
        for stage in [a,b,c]:
            for f in stage['fields'].values():
                data=Path(f['path']).read_bytes();assert len(data)==f['bytes'] and hashlib.sha256(data).hexdigest()==f['sha256']
        p=np.frombuffer(bytes.fromhex(case['slope_pushes'][0]['bytes_hex']),dtype='<f4').astype(np.float64)
        check(name+'_actual_48_byte_push',len(p)==12 and p[7]==0 and p[8]==np.float32(.9) and p[9]==.125)
        if name in ['erosion','deposition']:
            ep=np.frombuffer(bytes.fromhex(case['sediment_pushes'][0]['bytes_hex']),dtype='<f4').astype(np.float64)
            es,ed=sediment_reference(a,ep);error=max(float(np.max(np.abs(es-raw(b,'sand')))),float(np.max(np.abs(ed-raw(b,'sediment')))))
            bound=GAMMA128*max(1,float(np.max(np.abs(es)+np.abs(ed))))
            check(name+'_actual_sediment_kernel_reference',error<=bound,{'max_error_m':error,'forward_roundoff_bound_m':bound})
        es,et,prepared=slope_reference(b,c,p)
        actual_s=raw(c,'sand');actual_t=field(c,'mold_support_0',2);other=field(c,'mold_support_1',2)
        error_s=float(np.max(np.abs(es-actual_s)));error_t=float(np.max(np.abs(et-actual_t[:,:,0])))
        bound=GAMMA128*max(1,float(np.max(raw(b,'sand'))),float(np.max(np.abs(es))))
        check(name+'_shared_edge_sand_reference',error_s<=bound,{'max_error_m':error_s,'forward_roundoff_bound_m':bound})
        check(name+'_shared_edge_tag_reference',error_t<=bound,{'max_error_m':error_t,'forward_roundoff_bound_m':bound})
        tagged=actual_t[:,:,0]>0
        check(name+'_exact_complete_support_invariants',np.array_equal(actual_t,other) and np.isfinite(actual_t).all() and (actual_t[:,:,0]>=0).all() and (actual_t[:,:,0]<=actual_s).all() and np.array_equal(actual_t[:,:,1][tagged],actual_s[tagged]) and np.count_nonzero(actual_t[:,:,1][~tagged])==0)
        tag_drift=float(abs(actual_t[:,:,0].sum()-prepared.sum())*.125**2)
        affected=int(np.count_nonzero(et!=prepared))
        tag_bound=GAMMA128*max(1,affected)*max(float(prepared.max()),1e-8)*.125**2
        check(name+'_tag_shared_edge_closure',tag_drift<=tag_bound,{'absolute_drift_m3':tag_drift,'roundoff_bound_m3':tag_bound})
        previous_sand=raw(b,'sand')
        sand_drift=float(abs(actual_s.sum()-previous_sand.sum())*.125**2)
        sand_affected=int(np.count_nonzero(es!=previous_sand))
        sand_bound=GAMMA128*max(1,sand_affected)*max(1,float(previous_sand.max()))*.125**2
        check(name+'_sand_shared_edge_closure',sand_drift<=sand_bound,{'absolute_drift_m3':sand_drift,'roundoff_bound_m3':sand_bound})
        check(name+'_complete_sand_dual_slots_exact',np.array_equal(actual_s,raw(c,'spare_sand')))
        center=(128,128);metrics[name]={'center_sand_before':float(raw(b,'sand')[center]),'center_sand_after':float(actual_s[center]),'center_tag_before':float(field(a,'mold_support_0',2)[center][0]),'center_tag_after':float(actual_t[center][0]),'sand_max_reference_error_m':error_s,'tag_max_reference_error_m':error_t}
    check('erosion_weakens_layer',metrics['erosion']['center_tag_after']<metrics['erosion']['center_tag_before'])
    check('deposition_does_not_create_layer',metrics['deposition']['center_tag_after']==metrics['deposition']['center_tag_before'])
    check('wet_layer_moves_more_than_dry',metrics['slope_wet']['center_sand_after']<metrics['slope_dry']['center_sand_after'])
    check('thin_layer_moves_more_than_saturated',metrics['slope_thin']['center_sand_after']<metrics['slope_dry']['center_sand_after'])
    check('obstacle_blocks_slope',metrics['slope_obstacle']['center_sand_after']==metrics['slope_obstacle']['center_sand_before'])
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'metrics':metrics,'numerical_reference':'Float64 shared-edge booking versus GPU float32, gamma128 bound; complete field invariants remain exact. No change to old physics tolerances.','scope':'Single actual sediment/material dispatch with controlled upstream inputs; not full time integration, native or ordinary strict gate.'}
    (output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');return result['pass']

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True);passed=run(args.output);print('MATERIAL_OPERATOR_REFERENCE',passed);raise SystemExit(0 if passed else 1)
