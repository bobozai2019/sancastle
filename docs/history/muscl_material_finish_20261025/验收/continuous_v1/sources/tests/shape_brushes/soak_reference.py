"""Audit first-round measured data and final authoritative fields."""
import argparse,json,hashlib
from pathlib import Path
import numpy as np

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--evidence',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True);base=args.evidence.parent
    record=json.loads(args.evidence.read_text(encoding='utf-8'));checks=[]
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    def field(name,dtype='<f4',channels=1):
        data=(base/('soak_final_'+name+'.bin')).read_bytes()
        return np.frombuffer(data,dtype=dtype).astype(np.float64).reshape(256,256,channels).squeeze()
    for name in ['sand','water','sediment','momentum_x','momentum_z','spare_sand','spare_water','spare_sediment','spare_momentum_x','spare_momentum_z']:
        value=field(name);check(name+'_finite',np.isfinite(value).all())
        if 'momentum' not in name:check(name+'_nonnegative',(value>=0).all())
    for name in ['wetness','compaction','spare_wetness','spare_compaction']:
        value=field(name,'<f2');check(name+'_range',np.isfinite(value).all() and ((value>=0)&(value<=1)).all())
    tag=field('mold_support_0',channels=2);other=field('mold_support_1',channels=2);sand=field('sand')
    check('support_valid',np.isfinite(tag).all() and np.array_equal(tag,other) and (tag[:,:,0]>=0).all() and (tag[:,:,0]<=sand).all() and np.array_equal(tag[:,:,1],np.where(tag[:,:,0]>0,sand,0)))
    check('published_sand',np.array_equal(sand,field('published_sand')));check('published_water',np.array_equal(field('water'),field('published_water')))
    check('five_minutes',record['duration_us']>=300000000);check('all_tools_actual_success',all(any(a['tool']==tool and any(e['terminal']['result']['status']==1 for e in a['events']) for a in record['actions']) for tool in ['Castle','Wall','Shovel']))
    check('bounded_known_resources',all(s['shape']['rid_count']==69 and s['query_rids']==4 and s['pending']<=64 and s['stroke_points']<=256 and s['collision_shapes']<=64 for s in record['samples']))
    frame=np.asarray(record['frames_ms']);metrics={'frame_count':len(frame),'frame_ms_p50_p95_p99':np.percentile(frame,[50,95,99]).tolist(),'frame_ms_max':float(frame.max()),'completed_ticks':record['final_tick']-record['initial_tick'],'window_seconds':record['duration_us']/1e6,'actions_ms':[{'tool':a['tool'],'ms':a['elapsed_us']/1000,'actual_commands':len(a['events'])} for a in record['actions']],'missing':record['missing_metrics']+['separate_shape_material_water_stage_costs']}
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'metrics':metrics,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'functional boundedness and measured first-round costs; no invented latency/performance acceptance and no strict continuation acceptance'}
    (args.output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('SOAK_REFERENCE',result['pass'],len(checks));raise SystemExit(0 if result['pass'] else 1)
if __name__=='__main__':main()
