"""Fixed-bed CPU diagnostic initialized from exact GPU shovel state, not a release variant."""
import argparse,hashlib,json,time
from pathlib import Path
import numpy as np
from reference import Reference
POINTS=[[-1.5625,.0625],[-2.0625,.0625],[-2.5625,.0625]]
def main():
 p=argparse.ArgumentParser();p.add_argument('--case',choices=['bed_only_no_initial_momentum','reverse_initial_momentum'],required=True);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False);started=time.time();r=json.loads((a.input/'diagnosis.json').read_text());case=next(c for c in r['cases'] if c['id']=='flat_shovel');snap=next(s for s in case['snapshots'] if s['label']=='edited');before=next(s for s in case['snapshots'] if s['label']=='before');fields={};pins={}
 for key,item in snap['fields'].items():
  if key in ['control','decision']:continue
  raw=Path(item['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==item['sha256'];fields[key]=np.frombuffer(raw,dtype='<f4').astype('f8').reshape(256,256);pins[key]=item
 factor=1
 for key in fields:fields[key]=np.repeat(np.repeat(fields[key][64:192,64:192],factor,axis=0),factor,axis=1)
 momentum_factor=0.0 if a.case=='bed_only_no_initial_momentum' else -1.0
 fields['momentum_x']*=momentum_factor;fields['momentum_z']*=momentum_factor
 dx=.125/factor;n=128*factor;bed=fields['rock']+fields['sand'];state=np.stack([fields['water'],fields['momentum_x'],fields['momentum_z'],fields['sediment']]);control_eta=sum(np.frombuffer(Path(before['fields'][k]['path']).read_bytes(),dtype='<f4').astype('f8').reshape(256,256) for k in ['rock','sand','water']);control_eta=np.repeat(np.repeat(control_eta[64:192,64:192],factor,axis=0),factor,axis=1);solver=Reference(bed,dx,periodic=False);
 def probe(field,x,z):
  u=(x+8)/dx-.5;v=(z+8)/dx-.5;i,j=int(np.floor(u)),int(np.floor(v));fx,fz=u-i,v-j
  return float((1-fz)*((1-fx)*field[j,i]+fx*field[j,i+1])+fz*((1-fx)*field[j+1,i]+fx*field[j+1,i+1]))
 rows=[];advanced=0.;stats=[]
 for sample in range(61):
  while advanced<sample*.1-1e-10:
   state,st,_=solver.advance(state,min(1/30,sample*.1-advanced));advanced+=st['advanced_time_s'];stats.append(st);assert st['advanced_time_s']>0 and not st['capacity_exhausted']
  eta=bed+state[0];rows.append({'time_s':advanced,'delta_eta_m':[probe(eta-control_eta,x,z) for x,z in POINTS], 'boundary_max_eta_change_m':float(max(np.max(abs((eta-control_eta)[0,:])),np.max(abs((eta-control_eta)[-1,:])),np.max(abs((eta-control_eta)[:,0])),np.max(abs((eta-control_eta)[:,-1]))))});np.savez_compressed(a.output/('state_%03d.npz'%sample),state=state,bed=bed);print('REFERENCE_SAMPLE',sample,advanced,flush=True)
 y=np.array([row['delta_eta_m'] for row in rows]);windows=[]
 for i in range(51):
  half=.5*np.ptp(y[i:i+11],axis=0);qual=any(half[j]>=.0005 and half[j+1]>=.0005 for j in range(2));windows.append({'start_s':i*.1,'half_peak_to_peak_m':half.tolist(),'qualifies':bool(qual)})
 report={'schema':1,'scope':'Cause diagnostic only: GPU-derived post-shovel source in the validated central16m domain; initial momentum alone removed or reversed. Full2D float64 MC/RK fixed bed. Counterfactual cause isolation, not acceptance or a production change. Control is the exact initial uniform stationary lake; no production erosion/sources. This is neither fine-grid implementation nor performance work.','input_pins':pins,'source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),Path(__file__).with_name('reference.py')]},'points_xz_m':POINTS,'rows':rows,'windows':windows,'peak_to_peak_m':np.ptp(y,axis=0).tolist(),'qualifying_window_start_occupation_s':sum(w['qualifies'] for w in windows)*.1,'source_treatment':{'initial_momentum_factor':momentum_factor,'unchanged_fields':['rock','sand','water','sediment'],'scope':'Diagnostic counterfactual only; does not satisfy the frozen standard shovel input.'},'case':a.case,'grid_size':n,'dx_m':dx,'domain_extent_m':16.0,'refinement_initialization':'Original coarse source with only initial q components transformed as explicitly recorded. Same fixed point coordinates and stationary-lake control.','accepted_substeps':sum(s['accepted_substeps'] for s in stats),'rejected_trials':sum(s['rejected_trials'] for s in stats),'velocity_limit_count':sum(s['velocity_limited_cells'] for s in stats),'elapsed_wall_s':time.time()-started,'outcome':'complete'}
 (a.output/'result.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ['rows','windows','input_pins','gpu_max_h_error_m']},indent=2))
if __name__=='__main__':main()
