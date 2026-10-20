"""Reconstruct exact physical quantum counts from recorded Jolt callbacks."""
import argparse,hashlib,json,math
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--first-order',type=Path,required=True);p.add_argument('--muscl',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 if a.output.exists():raise FileExistsError(a.output)
 checks=[];runs=[]
 for folder in [a.first_order,a.muscl]:
  r=json.loads((folder/'diagnosis.json').read_text());manifest=json.loads((folder/'manifest.json').read_text());checks.append({'label':folder.name+':process','pass':r['pass'] and manifest['exit_code']==0 and manifest['outcome']=='pass'});cases=[]
  for case in r['cases']:
   counts={1:0,2:0,3:0};old_event=0;maximum_age=0.;samples=[]
   for snap in case['snapshots']:
    item=snap['props'];raw=Path(item['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==item['sha256'];v=json.loads(raw);q=v['quantum_s'];expected=math.floor((v['water_time_s']-v['origin_time_s']+1e-7)/q)
    checks.append({'label':case['id']+':'+snap['label']+':target','pass':v['target_steps']==expected and abs(v['admitted_time_s']-expected*q)<1e-7 and not v['error'] and not v['holds'] and v['evicted']==0})
    for e in v['events']:
     assert e['event_id']>old_event;old_event=e['event_id']
     if e['kind'] in ['physics','sleep_step']:
      data=e['data'];bid=data['body_id'];counts[bid]+=1
      if e['kind']=='physics':assert abs(data['state_step']-data['expected_step'])<1e-7 and not data['error']
     if e['kind']=='admit':maximum_age=max(maximum_age,e['data']['force_age_s'])
    for body in v['bodies']:
     bid=body['body_id'];checks.append({'label':case['id']+':'+snap['label']+':body'+str(bid),'pass':counts[bid]==expected and round(body['actual_time_s']/q)==expected})
    samples.append({'label':snap['label'],'water_time_s':v['water_time_s'],'target_steps':expected,'observed_callback_counts':dict(counts)})
   frames=sorted((folder/case['id']).glob('frame_*.png'));checks.append({'label':case['id']+':all_video_frames','pass':[f.name for f in frames]==['frame_%03d.png'%i for i in range(61)]});checks.append({'label':case['id']+':sample_age','pass':maximum_age<=.150001});cases.append({'id':case['id'],'samples':samples,'maximum_force_age_s':maximum_age})
  runs.append({'folder':str(folder.resolve()),'solver_id':r['solver_id'],'cases':cases})
 report={'outcome':'pass' if checks and all(c['pass'] for c in checks) else 'fail','checks':checks,'runs':runs,'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Counts real physics/sleep_step events from t0, compares each observed body quantum with completed water budget. Full 0-6s frame continuity. Runtime budgets unchanged.'};a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2));print(json.dumps({'outcome':report['outcome'],'checks':len(checks),'failures':[c for c in checks if not c['pass']]},indent=2))
if __name__=='__main__':main()
