"""Audit actual Jolt grants and force/pose paired response without replacing holds."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np

def analyze(folder,paused):
 r=json.loads((folder/'diagnosis.json').read_text());baseline=json.loads((paused/'diagnosis.json').read_text());fail=[];cases={};field_same=True
 for case,base in zip(r['cases'],baseline['cases']):
  records=[];last_event=0
  for snap,old in zip(case['snapshots'],base['snapshots']):
   for k in snap['fields']:
    if k not in ['control','decision'] and snap['fields'][k]['sha256']!=old['fields'][k]['sha256']:field_same=False
   item=snap['props'];p=Path(item['path']);raw=p.read_bytes()
   if hashlib.sha256(raw).hexdigest()!=item['sha256']:fail.append('props identity:'+str(p))
   row=json.loads(raw);row['time_s']=snap['time_s'];records.append(row)
   if row['error'] or row['evicted']:fail.append('error/trace eviction:'+case['id']+':'+snap['label'])
   if abs(row['water_time_s']-row['last_sample_time_s'])>1e-5:fail.append('stale terminal sample:'+snap['label'])
   for event in row['events']:
    if event['event_id']<=last_event:fail.append('nonmonotonic event id')
    last_event=event['event_id']
    if event['kind']=='admit' and event['data']['force_age_s']>.150001:fail.append('force age budget exceeded')
    if event['kind']=='physics' and (event['data']['error'] or abs(event['data']['state_step']-event['data']['expected_step'])>1e-7):fail.append('actual Jolt grant mismatch')
  cases['control' if case['id'].endswith('control') else 'shovel']=records
 curves={};responses={}
 for body_id in [1,2,3]:
  bodycurves={}
  for kind,records in cases.items():
   rows=[]
   for row in records:
    if row['label']=='before' and kind=='shovel':continue
    body=next(b for b in row['bodies'] if b['body_id']==body_id);events=[e for e in row['events'] if e['kind']=='point_force' and e['data']['body_id']==body_id];eta=np.array([e['data']['sample_eta'] for e in events]);force=np.array([e['data']['force_n'] for e in events]);u=np.array([e['data']['sample_u_m_s'] for e in events]);rows.append({'time_s':row['time_s'],'body':body,'force_record_count':len(events),'mean_sample_eta_m':float(eta.mean()) if len(eta) else None,'mean_force_n':force.mean(axis=0).tolist() if len(force) else None,'mean_sample_u_m_s':u.mean(axis=0).tolist() if len(u) else None})
   bodycurves[kind]=rows
  control,shovel=bodycurves['control'],bodycurves['shovel'];clock_gap=max(abs(c['body']['actual_time_s']-s['body']['actual_time_s']) for c,s in zip(control,shovel));
  if clock_gap>1e-7:fail.append('paired actual body clock mismatch:'+str(body_id))
  delta_position=np.array([r['body']['position_m'] for r in shovel])-np.array([r['body']['position_m'] for r in control]);delta_velocity=np.array([r['body']['linear_velocity_m_s'] for r in shovel])-np.array([r['body']['linear_velocity_m_s'] for r in control]);valid=[i for i in range(61) if control[i]['mean_force_n'] is not None and shovel[i]['mean_force_n'] is not None];dforce=np.array([np.array(shovel[i]['mean_force_n'])-np.array(control[i]['mean_force_n']) for i in valid]);deta=np.array([shovel[i]['mean_sample_eta_m']-control[i]['mean_sample_eta_m'] for i in valid]);responses[str(body_id)]={'maximum_paired_actual_clock_difference_s':clock_gap,'maximum_paired_position_difference_m':float(np.linalg.norm(delta_position,axis=1).max()),'maximum_paired_velocity_difference_m_s':float(np.linalg.norm(delta_velocity,axis=1).max()),'maximum_mean_point_force_difference_n':float(np.linalg.norm(dforce,axis=1).max()) if len(valid) else None,'maximum_sample_eta_difference_m':float(abs(deta).max()) if len(valid) else None,'valid_force_comparison_samples':len(valid),'delta_position_m':delta_position.tolist(),'delta_velocity_m_s':delta_velocity.tolist(),'force_comparison_times_s':[control[i]['time_s'] for i in valid],'delta_mean_point_force_n':dforce.tolist(),'delta_mean_sample_eta_m':deta.tolist()};curves[str(body_id)]=bodycurves
 for key in ['1','2']:
  a=responses[key]
  if a['valid_force_comparison_samples']<50 or a['maximum_paired_position_difference_m']<=1e-6 or (a['maximum_mean_point_force_difference_n'] or 0)<=1e-5:fail.append('no measurable response:'+key)
 return {'outcome':'pass' if not fail and field_same and r['pass'] else 'fail','solver_id':r['solver_id'],'physical_field_bytes_equal_to_paused_run':field_same,'failures':fail,'responses':responses,'curves':curves,'scope':'Existing bottle at frozen near x/z; existing plank at frozen far x/z; third existing stick authored. Real Jolt, original force model, original .15s sample age. Mean point force is reported per recorded force application; no missing/held force is filled with zero. Independent actual bodies include inertia, drag and terrain contacts. No performance claim.'}
def main():
 p=argparse.ArgumentParser();p.add_argument('--run',type=Path,required=True);p.add_argument('--paused',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 if a.output.exists():raise FileExistsError(a.output)
 r=analyze(a.run.resolve(),a.paused.resolve());a.output.parent.mkdir(parents=True,exist_ok=True);r['analyzer_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest();a.output.write_text(json.dumps(r,indent=2));print(json.dumps({'outcome':r['outcome'],'physical_field_bytes_equal_to_paused_run':r['physical_field_bytes_equal_to_paused_run'],'failures':r['failures'],'responses':{k:{n:v for n,v in b.items() if not isinstance(v,list)} for k,b in r['responses'].items()}},indent=2))
if __name__=='__main__':main()
