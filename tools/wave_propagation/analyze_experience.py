"""C03 dense edited-control raw-field audit. Preserves failed criteria."""
import argparse,hashlib,json,zipfile
from pathlib import Path
import numpy as np
POINTS=[[-1.5625,.0625],[-2.0625,.0625],[-2.5625,.0625]]
def load(folder):
 r=json.loads((folder/'diagnosis.json').read_text());fail=[];curves={};initial={};edited={}
 with zipfile.ZipFile(folder/'consumed_sources.zip') as z:
  for s,h in r['source_hashes'].items():
   if hashlib.sha256(z.read(s.removeprefix('res://'))).hexdigest()!=h:fail.append('source identity:'+s)
 for case in r['cases']:
  rows=[]
  for snap in case['snapshots']:
   fields={}
   for key,item in snap['fields'].items():
    raw=Path(item['path']).read_bytes()
    if len(raw)!=item['bytes'] or hashlib.sha256(raw).hexdigest()!=item['sha256']:fail.append('raw identity:'+str(item['path']))
    if key not in ['control','decision']:
     a=np.frombuffer(raw,dtype='<f4').astype(np.float64).reshape(256,256);fields[key]=a
     if not np.isfinite(a).all():fail.append('nonfinite:'+case['id']+':'+snap['label']+':'+key)
   if fields['water'].min()<0 or fields['sand'].min()<0:fail.append('negative:'+case['id']+':'+snap['label'])
   eta=fields['rock']+fields['sand']+fields['water'];points=[]
   for x,z in POINTS:
    ix,iz=int(x/.125+128),int(z/.125+128)
    points.append({'eta_m':float(eta[iz,ix]),'h_m':float(fields['water'][iz,ix]),'qx':float(fields['momentum_x'][iz,ix]),'qz':float(fields['momentum_z'][iz,ix])})
   row={'label':snap['label'],'time_s':snap['time_s'],'tick':snap['tick'],'points':points};rows.append(row)
   if snap['label']=='before':initial[case['id']]={k:v['sha256'] for k,v in snap['fields'].items() if k not in ['control','decision']}
   if snap['label']=='edited':edited={k:v['sha256'] for k,v in snap['fields'].items() if k not in ['control','decision']}
  control=case['id'].endswith('control');curves['control' if control else 'shovel']=[row for row in rows if row['label']!='before' or control]
 t=np.array([a['time_s'] for a in curves['control']]);te=np.array([a['time_s'] for a in curves['shovel']]);y=np.array([[p['eta_m'] for p in a['points']] for a in curves['shovel']])-np.array([[p['eta_m'] for p in a['points']] for a in curves['control']])
 if len(t)!=61 or len(te)!=61 or abs(t[-1]-6)>2e-5 or np.max(abs(t-te))>2e-6:fail.append('dense actual clock')
 if any(p['h_m']<=1e-5 for c in curves.values() for a in c for p in a['points']):fail.append('dry frozen point')
 if len(set(tuple(sorted(v.items())) for v in initial.values()))!=1:fail.append('paired initial mismatch')
 pp=np.ptp(y,axis=0);arrival=[]
 for i in range(3):
  ix=np.flatnonzero(abs(y[:,i]-y[0,i])>=max(1e-5,.1*pp[i]));arrival.append(float(t[ix[0]]) if len(ix) else None)
 windows=[]
 for start in range(51):
  half=.5*np.ptp(y[start:start+11],axis=0);adjacent=[bool(half[i]>=.0005 and half[i+1]>=.0005) for i in range(2)]
  windows.append({'start_s':float(t[start]),'end_s':float(t[start+10]),'half_peak_to_peak_m':half.tolist(),'adjacent_pair_above_threshold':adjacent,'qualifies_amplitude':any(adjacent)})
 active=[i for i,w in enumerate(windows) if w['qualifies_amplitude']];covered=set(j for i in active for j in range(i,i+10))
 return {'probe_pass':r['pass'],'solver_id':r['solver_id'],'mode':r['mode'],'failures':fail,'initial_field_identities':initial,'edited_field_identities':edited,'curves':curves,'actual_times_s':t.tolist(),'delta_eta_m':y.tolist(),'peak_to_peak_m':pp.tolist(),'arrival_10percent_peak_with_10um_floor_s':arrival,'arrival_order':all(a is not None for a in arrival) and arrival[0]<arrival[1]<arrival[2],'windows':windows,'qualifying_window_start_occupation_s':len(active)*.1,'qualifying_window_union_duration_s':len(covered)*.1,'source_hashes':r['source_hashes']}
def main():
 p=argparse.ArgumentParser();p.add_argument('--first-order',type=Path,required=True);p.add_argument('--muscl',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 if a.output.exists():raise FileExistsError(a.output)
 fo=load(a.first_order.resolve());mc=load(a.muscl.resolve());fail=fo['failures']+mc['failures'];same_initial=list(fo['initial_field_identities'].values())[0]==list(mc['initial_field_identities'].values())[0];same_edit=fo['edited_field_identities']==mc['edited_field_identities'];ratios=np.array(mc['peak_to_peak_m'])/np.array(fo['peak_to_peak_m']);median_ratio=float(np.median(ratios));duration=mc['qualifying_window_start_occupation_s']-fo['qualifying_window_start_occupation_s'];union=mc['qualifying_window_union_duration_s']-fo['qualifying_window_union_duration_s'];criteria={'same_initial':same_initial,'same_tool_field_result':same_edit,'same_sources':fo['source_hashes']==mc['source_hashes'],'far_field_median_ratio_at_least_1_5':median_ratio>=1.5,'arrival_order':mc['arrival_order'],'duration_gain_at_least_1s_start_occupation':duration>=1-1e-6,'duration_gain_at_least_1s_union':union>=1-1e-6}
 result={'schema':1,'scope':'G5 physical field criteria only. Visual coherence and real body response require separate evidence. Duration reports both qualifying window-start occupation and union coverage; no static-offset substitution. Arrival diagnostic first 10% own p2p with 10um floor, alongside full curves; no independent coherence acceptance.','outcome':'pass' if all(criteria.values()) and not fail else 'fail','criteria':criteria,'far_point_peak_to_peak_ratio':ratios.tolist(),'median_ratio':median_ratio,'duration_gain_start_occupation_s':duration,'duration_gain_union_s':union,'points_xz_m':POINTS,'first_order':fo,'muscl':mc,'failures':fail,'analyzer_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()};a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2));print(json.dumps({k:result[k] for k in ['outcome','criteria','median_ratio','duration_gain_start_occupation_s','duration_gain_union_s','failures']},indent=2))
if __name__=='__main__':main()
