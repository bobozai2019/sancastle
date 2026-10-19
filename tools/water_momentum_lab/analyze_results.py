"""Summarize raw lab evidence without modifying runs or inferring GPU time from CPU latency."""
import argparse,json,re
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'test_output/water_momentum_lab'
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def rows(folder):return [json.loads(s) for s in (folder/'metrics.jsonl').read_text(encoding='utf-8').splitlines()]
def pct(values):
 a=np.asarray(values,dtype=float)
 return {'count':len(a),**({f'p{n}':float(np.percentile(a,n)) for n in [50,95,99]} if len(a) else {})}

def effect(name):
 folder=OUT/name;data=rows(folder);commands=read(folder/'commands.json')['accepted'];groups={}
 for c in commands:
  if c['generation'] not in groups and c['a']=='(0.0, 0.0)' and c['b']=='(0.0, 0.0)':groups[c['generation']]={'mode':c['mode'],'op':c['operation']}
 result=[];series=[]
 for gen,info in groups.items():
  if len(result)>=9:break
  sample=[r for r in data if r['generation']==gen]
  unique={round(r['metrics'][20],7):r['metrics'] for r in sample}
  ts=np.array(sorted(unique));m=np.array([unique[t] for t in ts]);roi=m[:,12]*.015625
  dt=np.diff(ts);flow=-np.diff(roi)/dt
  nonzero=flow[np.abs(flow)>1e-5]
  return_s=None
  if len(nonzero):
   sign=np.sign(nonzero[0]);rev=np.flatnonzero(flow*sign< -1e-5)
   if len(rev):return_s=float(ts[rev[0]+1])
  row={**info,'generation':gen,'initial_max_speed_m_s':float(m[0,5]),'max_speed_m_s':float(m[:,5].max()),'roi_initial_m3':float(roi[0]),'roi_final_m3':float(roi[-1]),'peak_roi_net_outflow_m3_s':float(flow.max()) if len(flow) else None,'peak_roi_net_inflow_m3_s':float(flow.min()) if len(flow) else None,'first_reversal_sim_s':return_s,'water_mass_relative_max':float(np.max(np.abs(m[:,0]-m[0,0]))/m[0,0]),'actual_last_sim_s':float(ts[-1])}
  result.append(row);series.append({**info,'t':ts.tolist(),'roi_m3':roi.tolist(),'max_speed':m[:,5].tolist(),'flow_t':((ts[1:]+ts[:-1])*.5).tolist(),'net_outflow':flow.tolist()})
 report={'cases':result,'series':series,'flow_definition':'negative finite difference of fixed 1.5m circle ROI water volume / actual completed simulation dt; closed domain, no ROI sources; reduction float32 noise remains','reversal_threshold_m3_s':1e-5}
 (folder/'effect_analysis.json').write_text(json.dumps(report,indent=2))
 return report

def timing(name):
 folder=OUT/name;data=rows(folder);frame=read(folder/'frames.json');env=read(folder/'environment.json');commands=read(folder/'commands.json')
 for a,b in zip(frame,frame[1:]):b['wall_interval_ms']=(b['at_us']-a['at_us'])/1000.
 frame=frame[1:]
 for f in frame:f['engine_delta_ms']=f['ms'];f['ms']=f['wall_interval_ms']
 jobs={(r['generation'],r['serial']):r for r in data};pairs={};seen=set()
 for row in data:
  starts={}
  for t in row['timestamps']:
   unique=(t['frame'],t['name'],t['gpu_ns'])
   if unique in seen:continue
   seen.add(unique)
   match=re.fullmatch(r'lab_g(\d+)_m(\d+)_j(\d+)_(.*)_(start|end)',t['name'])
   if not match:continue
   gen,mode,serial=map(int,match.group(1,2,3));phase,edge=match.group(4,5);key=(gen,serial,phase)
   if edge=='start':starts[key]=t['gpu_ns']
   elif key in starts:
    value=(t['gpu_ns']-starts[key])/1e6
    pairs.setdefault((gen,serial),{'mode':mode})[phase]=value
 samples=[]
 for key,phases in pairs.items():
  if key not in jobs:continue
  job=jobs[key]
  samples.append({**phases,'generation':key[0],'serial':key[1],'command_id':job['command_id'],'recording_ms':job['recording_us']/1000.,'latency_ms':job['latency_us']/1000.,'queue_age_ms':job['command_age_us']/1000.,'completed_us':job['completed_us'],'queue':job['queue'],'metrics':job['metrics']})
 summary={}
 for mode in range(3):
  all_jobs=[s for s in samples if s['mode']==mode]
  edits=[s for s in all_jobs if s['command_id']>0 and 'edit' in s and 'audit' in s]
  summary[str(mode)]={'edit_with_audit_ms':pct([s['edit']+s['audit'] for s in edits]),'edit_ms':pct([s['edit'] for s in edits]),'audit_ms':pct([s['audit'] for s in edits]),'water_ms':pct([s['water'] for s in all_jobs if 'water' in s]),'publish_ms':pct([s['publish'] for s in all_jobs if 'publish' in s]),'cpu_recording_ms':pct([s['recording_ms'] for s in all_jobs]),'completion_latency_ms':pct([s['latency_ms'] for s in all_jobs]),'queue_age_ms':pct([s['queue_age_ms'] for s in edits]),'frame_ms':pct([f['ms'] for f in frame if f['mode']==mode])}
 group_metrics={}
 for gen in sorted(set(s['generation'] for s in samples if s['command_id']>0)):
  edits=[s for s in samples if s['generation']==gen and s['command_id']>0 and 'edit' in s and 'audit' in s]
  group_metrics[gen]={'mode':edits[0]['mode'],'edit_with_audit_ms':pct([s['edit']+s['audit'] for s in edits])['p95'],'frame_ms':pct([f['ms'] for f in frame if f['generation']==gen])['p95'],'queue_age_ms':pct([s['queue_age_ms'] for s in edits])['p95']}
 a1=[g for g in group_metrics.values() if g['mode']==1];b=[g for g in group_metrics.values() if g['mode']==2]
 paired_noise={}
 if len(a1)==len(b) and len(b)>=3:
  for metric in ['edit_with_audit_ms','frame_ms','queue_age_ms']:
   differences=np.array([y[metric]-x[metric] for x,y in zip(a1,b)])
   paired_noise[metric]={'paired_differences':differences.tolist(),'mad':float(np.median(np.abs(differences-np.median(differences))))}
 if 'soak' in name:paired_noise=read(OUT/'cost_low_final_v2/performance_analysis.json')['paired_noise']
 start=min(r['completed_us'] for r in data);end=max(r['completed_us'] for r in data)
 intervals=[]
 # First/last operation windows exclude the 30s release observation.
 for label,lo,hi in [('early',10,40),('late',270,300)]:
  edits=[s for s in samples if s['command_id']>0 and lo<=(s['completed_us']-start)/1e6<hi and 'edit' in s and 'audit' in s]
  f=[f['ms'] for f in frame if lo<=(f['at_us']-start)/1e6<hi]
  intervals.append({'window':label,'edit_with_audit_ms':pct([s['edit']+s['audit'] for s in edits]),'frame_ms':pct(f),'queue_age_ms':pct([s['queue_age_ms'] for s in edits])})
 bins=[]
 for lo in range(10,300,10):
  edits=[s for s in samples if s['command_id']>0 and lo<=(s['completed_us']-start)/1e6<lo+10 and 'edit' in s and 'audit' in s]
  fs=[f['ms'] for f in frame if lo<=(f['at_us']-start)/1e6<lo+10]
  bins.append({'start_s':lo,'edit_p95_ms':pct([s['edit']+s['audit'] for s in edits]).get('p95'),'frame_p95_ms':pct(fs).get('p95'),'age_p95_ms':pct([s['queue_age_ms'] for s in edits]).get('p95')})
 degradation={}
 if intervals[1]['edit_with_audit_ms']['count']:
  for metric,key in [('edit_with_audit_ms','edit_p95_ms'),('frame_ms','frame_p95_ms'),('queue_age_ms','age_p95_ms')]:
   early=intervals[0][metric]['p95'];late=intervals[1][metric]['p95'];noise=[b[key] for b in bins[:3] if b[key] is not None]
   med=np.median(noise);mad=float(np.median(np.abs(np.asarray(noise)-med)));paired_mad=paired_noise[metric]['mad'];budget=max(.1*early,3*paired_mad)
   degradation[metric]={'early_p95':early,'late_p95':late,'growth':late-early,'early_bin_mad':mad,'paired_cost_noise_mad':paired_mad,'budget':budget,'passed':late-early<=budget}
 initial=data[0]['metrics'][0];mass=max(abs(r['metrics'][0]-initial)/initial for r in data) if 'soak' in name else None
 raw_bins=read(folder/'bins.json') if (folder/'bins.json').exists() else []
 b_after=[b for b in raw_bins if b['wall_s']>=10]
 available=bool(samples) and any(s.get('edit',0)>0 and s.get('audit',0)>0 for s in samples)
 report={'environment':env,'modes':summary,'timestamp_samples':len(samples),'gpu_timing_available':available,'accepted':len(commands['accepted']),'rejected':commands['rejected'],'raw_frame_count':len(frame),'real_wall_observation_s':(end-start)/1e6,'water_relative_max':mass,'nonfinite_max':max(r['metrics'][3] for r in data),'queue_max':max(r['queue'] for r in data),'intervals':intervals,'ten_second_timing_bins':bins,'degradation':degradation,'resource_ranges':{k:[min(b[k] for b in b_after),max(b[k] for b in b_after)] for k in ['objects','video_mem'] if b_after},'gpu_edit_target_pass':available and summary['2']['edit_with_audit_ms'].get('p95',float('inf'))<=2,'frame_target_pass':summary['2']['frame_ms'].get('p95',float('inf'))<=33.3,'timestamp_unit':'nanoseconds in this Godot4.7.2 D3D12 backend; deltas divided by 1e6 for milliseconds','phase_samples':samples}
 report['frame_metric']='monotonic adjacent _process callback interval from at_us; original Godot delta may be smoothed and remains untouched in frames.json'
 report['paired_noise']=paired_noise
 (folder/'performance_analysis.json').write_text(json.dumps(report,indent=2))
 return {k:v for k,v in report.items() if k!='phase_samples'}

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('run');parser.add_argument('--effect',action='store_true');a=parser.parse_args()
 result=effect(a.run) if a.effect else timing(a.run)
 if a.effect:result=result['cases']
 print(json.dumps(result,indent=2))
