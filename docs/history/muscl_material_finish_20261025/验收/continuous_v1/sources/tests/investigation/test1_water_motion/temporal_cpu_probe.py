"""Controlled continuation from test1, with explicitly experimental boundary release."""
import argparse,json,time
from pathlib import Path
import numpy as np
from model import velocity,height,advection,forcing,load_inputs,OUT,DX

p=argparse.ArgumentParser();p.add_argument('--seconds',type=float,default=20);p.add_argument('--mode',choices=['hold','release','zero_velocity'],default='release');args=p.parse_args()
DEST=OUT.parent/('cpu_'+args.mode+'_v1');DEST.mkdir(exist_ok=False)
a=np.load(OUT/'e6083/decoded.npy').astype(np.float32)
flags,air,obs=load_inputs();floor=a[:,:,3].copy()
if args.mode=='zero_velocity':a[:,:,:2]=0
rows=[];started=time.monotonic()
def sample(t):
 h=np.maximum(a[:,:,2]-.05,0);wet=h>.005;shore=wet&(floor>1.05)&(floor<2)
 rows.append({'t':t,'water_proxy':float(h.sum()*DX*DX),'shore_water_proxy':float(h[floor>1.05].sum()*DX*DX),
  'shore_wet_cells':int(shore.sum()),'onshore_cells':int((shore&(a[:,:,0]<-.05)).sum()),'return_cells':int((shore&(a[:,:,0]>.05)).sum()),
  'shore_mean_vx':float(a[:,:,0][shore].mean()) if shore.any() else 0,'speed_wet_mean':float(np.linalg.norm(a[:,:,:2],axis=-1)[wet].mean()),
  'nonfinite':int((~np.isfinite(a)).sum()),'min_amount':float(a[:,:,2].min()),'max_amount':float(a[:,:,2].max())})
 np.save(DEST/('state_%04d.npy'%round(t*40)),a)
sample(0)
for tick in range(1,round(args.seconds*40)+1):
 t=tick/40
 for _ in range(3):a=advection(height(velocity(a)))
 u=np.clip((t-2)/4,0,1);s=u*u*(3-2*u)
 override=1.6163164377212524*(1-s) if args.mode!='hold' else 1.6163164377212524
 a=forcing(a,flags,air,obs,284.71783447265625+t,override)
 if tick%40==0:
  sample(t);(DEST/'progress.json').write_text(json.dumps(rows,indent=2))
(DEST/'result.json').write_text(json.dumps({'mode':args.mode,'seconds':args.seconds,'wall_elapsed_s':time.monotonic()-started,'scope':'adaptation-time continuation, immutable inputs per phase, fixed sand; not original wall-time replay','rows':rows},indent=2));print(json.dumps(rows,indent=2))
