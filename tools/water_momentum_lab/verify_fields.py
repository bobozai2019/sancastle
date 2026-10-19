"""Independent NumPy edit reference. GPU transport fields are measured separately."""
import argparse, json, hashlib
from pathlib import Path
import numpy as np

parser=argparse.ArgumentParser()
parser.add_argument('run',type=Path)
args=parser.parse_args(); out=args.run
env=json.loads((out/'environment.json').read_text(encoding='utf-8'))
n=env['grid']; x,z=np.meshgrid((np.arange(n,dtype=np.float64)+.5-n/2)*.125,(np.arange(n,dtype=np.float64)+.5-n/2)*.125)
position=np.stack([x,z],axis=-1); norm=np.linalg.norm(position,axis=-1)
direction=np.divide(position,norm[:,:,None],out=np.zeros_like(position),where=norm[:,:,None]>0)
def weight(offset=0):
 r=np.sqrt((x-offset)**2+z*z)/.75
 return np.maximum(1-r*r,0)**2
w=weight(); checks=[]
def check(ok,name,**kw):checks.append(dict(passed=bool(ok),name=name,**kw))
def field(name):return np.fromfile(out/(name+'.rgba32f'),dtype='<f4').reshape(n,n,4)
for mode in range(3):
 for op in range(3):
  actual=field(f'mode{mode}_op{op}_edit')
  db=(-.2 if op==0 else .2)*w
  if op==2:db=.2*(.5*weight(1.5)+.5*weight(-1.5)-w)
  bed=(.5+db).astype(np.float32)
  db=bed.astype(np.float64)-.5
  dv=np.zeros_like(db) if mode==0 else (np.maximum(db,0) if mode==1 else db/.2)
  q=.3*dv[:,:,None]*direction
  expected=np.concatenate([bed[:,:,None],np.full((n,n,1),np.float32(.3)),q],axis=2)
  err=np.abs(actual-expected); tolerance=2e-6+2e-5*np.abs(expected)
  check(np.all(err<=tolerance),f'CPU GPU mode{mode} op{op}',max_error=float(err.max()),max_error_location=list(map(int,np.unravel_index(err.argmax(),err.shape))))
  initial_h=np.full((n,n),.3,dtype=np.float32)
  check(actual[:,:,1].tobytes()==initial_h.tobytes(),f'edit h byte preserved mode{mode} op{op}')
  support=np.abs(db)>0
  check(np.all(actual[:,:,2:][~support]==0),f'outside q byte preserved mode{mode} op{op}')
  if op==2:check(abs(float((actual[:,:,0].astype('f8')-.5).sum()*.015625))<=2e-5,f'transfer sand account mode{mode}')
  initial_water=float(initial_h.astype('f8').sum()*.015625)
  for k in range(6):
   f=field(f'mode{mode}_op{op}_t{k}')
   water=float(f[:,:,1].astype('f8').sum()*.015625)
   check(np.isfinite(f).all() and (f[:,:,:2]>=0).all() and abs(water-initial_water)/initial_water<=.005,f'transport mode{mode} op{op} time{k}',water_m3=water,mass_relative_error=abs(water-initial_water)/initial_water)
a=field('sampling_1')
for samples in [8,32]:
 b=field(f'sampling_{samples}')
 difference=float(np.linalg.norm(b[:,:,2:]-a[:,:,2:])/max(np.linalg.norm(a[:,:,2:]),1e-20))
 check(difference<=.01,f'path sampling {samples}',q_norm_relative_difference=difference,bed_max_difference=float(np.abs(b[:,:,0]-a[:,:,0]).max()))
suite=json.loads((out/'suite.json').read_text(encoding='utf-8'))
if (out/'sampling_batch8.rgba32f').exists():
 check(np.allclose(field('sampling_batch8'),field('sampling_8'),atol=2e-6,rtol=2e-5),'batch partition invariant')
if (out/'curved_L.rgba32f').exists():
 f=field('curved_L')
 # Center is farther than radius from both legs; the old diagonal fan
 # touched this cell even though the pointer never crossed it.
 center=f[n//2,n//2]
 check(np.array_equal(center,np.array([.5,.3,0,0],dtype=np.float32)),'curved polyline no diagonal fan')
for p in out.glob('*.sediment32f'):
 check(not any(p.read_bytes()),'sediment byte preserved '+p.stem)
if (out/'frequency_30.rgba32f').exists():
 for fps in [60,144]:check(np.array_equal(field('frequency_30'),field(f'frequency_{fps}')),f'actual-sim-clock 30 vs {fps} FPS')
check(all(row['pass'] for row in suite),'Godot suite all checks',count=len(suite))
report={'passed':all(c['passed'] for c in checks),'checks':checks,'scope':'Edit CPU/GPU reference, closed water mass, deterministic straight-path sampling; does not prove visual quality or performance.'}
(out/'field_verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({'passed':report['passed'],'checks':len(checks),'failed':[c for c in checks if not c['passed']]},indent=2))
raise SystemExit(0 if report['passed'] else 1)
