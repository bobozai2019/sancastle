"""Fixed-bed CPU diagnostic initialized from exact GPU shovel state, not a release variant."""
import argparse,hashlib,json,time
from pathlib import Path
import numpy as np
from reference import Reference
POINTS=[[-1.5625,.0625],[-2.0625,.0625],[-2.5625,.0625]]
def main():
 p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False);started=time.time();r=json.loads((a.input/'diagnosis.json').read_text());case=next(c for c in r['cases'] if c['id']=='flat_shovel');snap=next(s for s in case['snapshots'] if s['label']=='edited');before=next(s for s in case['snapshots'] if s['label']=='before');fields={};pins={}
 for key,item in snap['fields'].items():
  if key in ['control','decision']:continue
  raw=Path(item['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==item['sha256'];fields[key]=np.frombuffer(raw,dtype='<f4').astype('f8').reshape(256,256);pins[key]=item
 bed=fields['rock']+fields['sand'];state=np.stack([fields['water'],fields['momentum_x'],fields['momentum_z'],fields['sediment']]);control_eta=sum(np.frombuffer(Path(before['fields'][k]['path']).read_bytes(),dtype='<f4').astype('f8').reshape(256,256) for k in ['rock','sand','water']);solver=Reference(bed,.125,periodic=False);indices=[(int(z/.125+128),int(x/.125+128)) for x,z in POINTS];rows=[];advanced=0.;stats=[]
 for sample in range(61):
  while advanced<sample*.1-1e-10:
   state,st,_=solver.advance(state,min(1/30,sample*.1-advanced));advanced+=st['advanced_time_s'];stats.append(st);assert st['advanced_time_s']>0 and not st['capacity_exhausted']
  eta=bed+state[0];rows.append({'time_s':advanced,'delta_eta_m':[float(eta[z,x]-control_eta[z,x]) for z,x in indices]});np.savez_compressed(a.output/('state_%03d.npz'%sample),state=state,bed=bed);print('REFERENCE_SAMPLE',sample,advanced,flush=True)
 y=np.array([row['delta_eta_m'] for row in rows]);windows=[]
 for i in range(51):
  half=.5*np.ptp(y[i:i+11],axis=0);qual=any(half[j]>=.0005 and half[j+1]>=.0005 for j in range(2));windows.append({'start_s':i*.1,'half_peak_to_peak_m':half.tolist(),'qualifies':bool(qual)})
 gpu=[s for s in case['snapshots'] if s['label']!='before'];errors=[]
 for i,s in enumerate(gpu):
  h=np.frombuffer(Path(s['fields']['water']['path']).read_bytes(),dtype='<f4').reshape(256,256);v=np.load(a.output/('state_%03d.npz'%i))['state'];errors.append(float(abs(v[0]-h).max()))
 report={'schema':1,'scope':'Cause diagnostic only: exact coarse GPU post-shovel bed/state, full 2D float64 MC/RK fixed bed. Control is the exact initial uniform stationary lake; no production erosion/sources. This is neither fine-grid implementation nor performance work.','input_pins':pins,'source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),Path(__file__).with_name('reference.py')]},'points_xz_m':POINTS,'rows':rows,'windows':windows,'peak_to_peak_m':np.ptp(y,axis=0).tolist(),'qualifying_window_start_occupation_s':sum(w['qualifies'] for w in windows)*.1,'gpu_max_h_error_m':errors,'accepted_substeps':sum(s['accepted_substeps'] for s in stats),'rejected_trials':sum(s['rejected_trials'] for s in stats),'velocity_limit_count':sum(s['velocity_limited_cells'] for s in stats),'elapsed_wall_s':time.time()-started,'outcome':'complete'}
 (a.output/'result.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ['rows','windows','input_pins','gpu_max_h_error_m']},indent=2))
if __name__=='__main__':main()
