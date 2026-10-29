"""Final-template retention, destructive edits and real wave evolution audit."""
import argparse,json,math,hashlib
from pathlib import Path
import numpy as np
from shovel_reference import raw,A

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--evidence-root',type=Path)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True);source=args.evidence_root or args.output.parent
    checks=[];metrics={}
    def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
    axis=(np.arange(256)+.5-128)*.125;x,z=np.meshgrid(axis,axis);roi=(abs(x)<=2.5)&(abs(z)<=2.5);gap=(abs(x)<1.9)&(abs(z-1.25)<.125)
    for mode in ['castle_intact','castle_damaged','wet_wave']:
        record=json.loads((source/mode/'evolution.json').read_text(encoding='utf-8'))
        check(mode+'_900_actual_ticks',record['completed_ticks']==900 and record['tick_duration_rational']==[1,30])
        check(mode+'_seven_samples',[s['tick'] for s in record['samples']]==list(range(0,901,150)))
        base=raw(record['phases']['initial'],'rock')+raw(record['phases']['initial'],'sand')
        formed=record['phases']['formed'];height0=raw(formed,'rock')+raw(formed,'sand')-base;cutoff=.1*float(height0[roi].max());mask0=(height0>=cutoff)&roi
        initial=record['samples'][0];rows=[]
        for sample in record['samples']:
            sand=raw(sample,'sand');height=raw(sample,'rock')+sand-base;tag=raw(sample,'mold_support_0',2);pair=raw(sample,'mold_support_1',2)
            check(mode+str(sample['tick'])+'_support_valid',np.isfinite(tag).all() and (tag[:,:,0]>=0).all() and (tag[:,:,0]<=sand).all() and np.array_equal(tag,pair) and np.array_equal(tag[:,:,1],np.where(tag[:,:,0]>0,sand,0)))
            comp=raw(sample,'compaction',dtype='<f2');water=raw(sample,'water');sed=raw(sample,'sediment')
            check(mode+str(sample['tick'])+'_fields_valid',np.isfinite(sand).all() and (sand>=0).all() and np.isfinite(water).all() and (water>=0).all() and np.isfinite(sed).all() and (sed>=0).all() and np.isfinite(comp).all() and ((comp>=0)&(comp<=1)).all())
            if mode!='wet_wave':check(mode+str(sample['tick'])+'_actually_dry',np.count_nonzero(water)==0)
            check(mode+str(sample['tick'])+'_published_surface',sample['fields']['sand']['sha256']==sample['fields']['published_sand']['sha256'] and sample['fields']['water']['sha256']==sample['fields']['published_water']['sha256'])
            mask=(height>=cutoff)&roi;union=(mask0|mask).sum()
            rows.append({'tick':sample['tick'],'peak_ratio':float(height[roi].max()/height0[roi].max()),'iou':float((mask0&mask).sum()/union),'gap_peak_m':float(height[gap].max()),'gap_tag_max_m':float(tag[:,:,0][gap].max()),'gap_restored_fraction':float(np.mean(height[gap]>=height0[gap]-.05)),'sand_plus_sediment_m3':math.fsum((sand+sed).flat)*A,'tag_m3':math.fsum(tag[:,:,0].flat)*A,'max_water_m':float(water.max())})
        metrics[mode]=rows
        if mode=='castle_intact':check('final_castle_mat01',rows[-1]['peak_ratio']>=.8 and rows[-1]['iou']>=.8,rows[-1])
        elif mode=='castle_damaged':
            check('castle_cut_below_base_no_tag',rows[0]['gap_peak_m']<0 and rows[0]['gap_tag_max_m']==0,rows[0])
            check('castle_not_restored_to_template',rows[-1]['gap_restored_fraction']==0,rows[-1])
        else:
            check('actual_wave_admitted',len(record['wave_requests'])==1 and record['wave_requests'][0]['profile_id']=='test_packet')
            check('wet_shape_evolves',any(initial['fields'][key]['sha256']!=record['samples'][-1]['fields'][key]['sha256'] for key in ['sand','mold_support_0','compaction']))
            check('wet_water_foam_response',initial['fields']['water']['sha256']!=record['samples'][-1]['fields']['water']['sha256'] and any(initial['fields'][key]['sha256']!=s['fields'][key]['sha256'] for s in record['samples'][1:] for key in ['foam0','foam1']))
            check('wet_presentation_tick_clock',record['presentation']=='tick/30' and abs(record['metadata']['visual_time']-30)<1e-8)
        check(mode+'_no_implicit_sand_source',all(record['metadata'][key]==record['initial_metadata'][key] for key in ['source','sink','inventory']))
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'metrics':metrics,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'30 simulation seconds final geometry/material/complete surfaces; no performance/ordinary strict verdict'}
    (args.output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('SHAPE_EVOLUTION_REFERENCE',result['pass'],len(checks));raise SystemExit(0 if result['pass'] else 1)
if __name__=='__main__':main()
