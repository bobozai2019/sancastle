"""Audit actual wall retention and damage; erosion refill is not template healing."""
import argparse
import hashlib
import json
import struct
from pathlib import Path
import numpy as np
from retention_reference import raw


def support(sample, slot=0):
    item=sample['fields']['mold_support_'+str(slot)]
    data=Path(item['path']).read_bytes()
    assert len(data)==item['bytes'] and hashlib.sha256(data).hexdigest()==item['sha256']
    return np.frombuffer(data,dtype='<f4').astype(np.float64).reshape(256,256,2)


def run(output):
    records={n:json.loads((output.parent/n/'damage_evidence.json').read_text()) for n in ['intact','trench']}
    checks=[];metrics={}
    def check(name, passed, detail=None): checks.append({'name':name,'pass':bool(passed),'detail':detail})
    coords=(np.arange(256)+.5-128)*.125;x,z=np.meshgrid(coords,coords)
    wall=(np.abs(x)<=1.75)&(np.abs(z)<=.75)
    gap=(np.abs(x)<=.1875)&(np.abs(z)<=.1875)
    for mode,record in records.items():
        consumed_tick=struct.unpack('<d',bytes.fromhex(record['tick_duration_float64_hex']))[0]
        check(mode+'_completed_30s',record['completed_ticks']==900 and record['tick_duration_rational']==[1,30] and consumed_tick==1/30)
        check(mode+'_seven_samples',[s['tick'] for s in record['samples']]==list(range(0,901,150)))
        formed=record['phases']['formed'];h0=raw(formed,'rock')+raw(formed,'sand')
        cutoff=.1*float(h0[wall].max());mask0=(h0>=cutoff)&wall
        rows=[]
        for sample in record['samples']:
            h=raw(sample,'rock')+raw(sample,'sand');s=raw(sample,'sand');tag=support(sample);other=support(sample,1)
            valid=np.isfinite(tag).all() and (tag[:,:,0]>=0).all() and (tag[:,:,0]<=s).all() and np.array_equal(tag,other)
            tagged=tag[:,:,0]>0
            valid=valid and np.array_equal(tag[:,:,1][tagged],s[tagged]) and np.count_nonzero(tag[:,:,1][~tagged])==0
            check(mode+'_support_legal_tick_'+str(sample['tick']),valid)
            check(mode+'_material_legal_tick_'+str(sample['tick']),np.isfinite(s).all() and (s>=0).all() and np.isfinite(raw(sample,'compaction')).all() and ((raw(sample,'compaction')>=0)&(raw(sample,'compaction')<=1)).all())
            mask=(h>=cutoff)&wall;iou=float((mask0&mask).sum()/(mask0|mask).sum())
            rows.append({'tick':sample['tick'],'peak_ratio':float(h[wall].max()/h0[wall].max()),'iou':iou,'gap_peak_m':float(h[gap].max()),'gap_tag_max_m':float(tag[:,:,0][gap].max()),'total_sand_plus_sediment_m3':float((s+raw(sample,'sediment')).sum()*.125**2),'total_tag_m3':float(tag[:,:,0].sum()*.125**2),'gap_restored_fraction':float(np.mean(h[gap]>=h0[gap]-.05)),'max_water_m':float(raw(sample,'water').max())})
        metrics[mode]=rows
        if mode=='intact':check('actual_wall_mat01_30s',rows[-1]['peak_ratio']>=.8 and rows[-1]['iou']>=.8,rows[-1])
        else:
            check('trench_crosses_wall_below_base',rows[0]['gap_peak_m']<0 and rows[0]['gap_tag_max_m']==0,rows[0])
            check('trench_not_restored_to_template_30s',rows[-1]['gap_restored_fraction']==0 and rows[-1]['gap_peak_m']<.3,rows[-1])
        initial=rows[0]['total_sand_plus_sediment_m3']
        drift=max(abs(row['total_sand_plus_sediment_m3']-initial) for row in rows)
        # Keep full raw mass drift as an observation, not a newly invented gate.
        # The running original sand audit retains its existing closure threshold.
        record['observed_max_mass_drift_m3']=drift
        check(mode+'_external_ledger_constant',record['metadata']['source']==record['initial_source'] and record['metadata']['sink']==record['initial_sink'])
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'metrics':metrics,'observed_max_mass_drift_m3':{n:r['observed_max_mass_drift_m3'] for n,r in records.items()},'scope':'Wall retention plus damage observations only; castle/material transport/native and strict ordinary gate incomplete.'}
    (output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result['pass']


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True);passed=run(args.output)
    print('MATERIAL_DAMAGE_REFERENCE',passed);raise SystemExit(0 if passed else 1)
