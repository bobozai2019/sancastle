"""Independent raw-state limiter and rejected transaction audit."""
import argparse,json,hashlib
from pathlib import Path
import numpy as np
from shovel_reference import raw

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--evidence',type=Path)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    source=args.evidence or args.output.parent/'water_guard/water_guards.json'
    cases=json.loads(source.read_text(encoding='utf-8'));checks=[];metrics=[]
    def check(name,value):checks.append({'name':name,'pass':bool(value)})
    for case in cases:
        r=case['result'];before,after=case['before'],case['after']
        if case['mode']=='clamp':
            h=raw(after,'water');speed=np.divide(np.hypot(raw(after,'momentum_x'),raw(after,'momentum_z')),h,out=np.zeros_like(h),where=h>.001)
            check('binary32_speed_cap',np.all(speed<=4+8*(2**-24)*4))
            check('actual_clamp_count',r['status']==1 and r['clamp_count']>0)
            metrics.append({'max_speed_m_s':float(speed.max()),'clamp_count':r['clamp_count']})
        else:
            check('over_cfl_rejected',r['status']==3 and r['error_code']==17)
            check('all27_atomic',all(before['fields'][k]['sha256']==after['fields'][k]['sha256'] for k in before['fields']))
    result={'pass':all(c['pass'] for c in checks),'checks':checks,'metrics':metrics,'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (args.output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('WATER_GUARD_REFERENCE',result['pass']);raise SystemExit(0 if result['pass'] else 1)
if __name__=='__main__':main()
