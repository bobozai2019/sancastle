"""Five-minute raw field, cumulative all-tick monitor and closed-stock audit."""
import argparse,hashlib,json,struct,zipfile
from pathlib import Path
import numpy as np

def analyze(folder,full=False):
 r=json.loads((folder/'result.json').read_text());fail=[];rows=[];initial=None;previous_comp=None;last_tick=-1;archive=folder/'consumed_sources.zip'
 with zipfile.ZipFile(archive) as z:
  for key,h in r['configuration']['sources'].items():
   if hashlib.sha256(z.read(key.removeprefix('res://'))).hexdigest()!=h:fail.append('source:'+key)
 def read(s,name,dtype='<f4',channels=1):
  a=s['fields'][name];raw=Path(a['path']).read_bytes()
  if len(raw)!=a['bytes'] or hashlib.sha256(raw).hexdigest()!=a['sha256']:fail.append('identity:'+s['label']+'/'+name)
  return np.frombuffer(raw,dtype=dtype).reshape((256,256,channels) if channels>1 else (256,256))
 base=next((s for s in r['snapshots'] if s['label']=='edited'),r['snapshots'][0]);area=.125**2
 def stock(s):
  h=read(s,'water').astype('f8');sand=read(s,'sand').astype('f8');sed=read(s,'sediment').astype('f8');obstacle=read(s,'obstacle','u1')>=128;c=np.frombuffer(Path(s['fields']['control']['path']).read_bytes(),dtype='<f4');return h,sand,sed,obstacle,c
 bh,bs,bc,obstacle,control0=stock(base);water0=bh[~obstacle].sum()*area;solid0=(bs+bc).sum()*area
 for s in r['snapshots']:
  for key,item in s['fields'].items():
   p=Path(item['path']);raw=p.read_bytes()
   if len(raw)!=item['bytes'] or hashlib.sha256(raw).hexdigest()!=item['sha256']:fail.append('raw:'+str(p))
  h,sand,sed,_,control=stock(s);qx=read(s,'momentum_x');qz=read(s,'momentum_z');wet=read(s,'wetness','<f2');comp=read(s,'compaction','<f2');support=read(s,'mold_support',channels=2)
  if not all(np.isfinite(v).all() for v in [h,sand,sed,qx,qz,wet,comp,support]) or min(h.min(),sand.min(),sed.min())<0:fail.append('invalid fields:'+s['label'])
  if wet.min()<0 or wet.max()>1 or comp.min()<0 or comp.max()>1:fail.append('material bounds:'+s['label'])
  if previous_comp is not None and np.any(comp<previous_comp):fail.append('compaction decrease:'+s['label'])
  previous_comp=comp.copy()
  if np.any(support[:,:,0]<0) or np.any(support[:,:,0]>sand):fail.append('support range:'+s['label'])
  tags=support[:,:,0]>0
  if not np.array_equal(support[:,:,1][tags],sand[tags].astype('f4')) or np.any(support[~tags].view('<u4')!=0):fail.append('support reference:'+s['label'])
  for name in ['sand','sediment','wetness','compaction','mold_support']:
   if r['coupling_enabled'] and s['fields'][name]['sha256']!=s['fields'][name+'_spare']['sha256']:fail.append('spare:'+s['label']+'/'+name)
  monitor=Path(s['fields']['soak_monitor']['path']).read_bytes();drift=struct.unpack_from('<f',monitor,0)[0];flags,ticks=struct.unpack_from('<II',monitor,4);tick=int(s['tick'])
  if flags or ticks!=tick or tick<last_tick:fail.append('all-tick monitor:'+s['label'])
  last_tick=tick
  if r['case_id'].startswith('lake_') and drift>.0001:fail.append('all-tick static drift:'+s['label'])
  stats=np.frombuffer(Path(s['fields']['safety']['path']).read_bytes(),dtype='<u4');counts=[int(stats[j])+2**32*int(stats[j+1]) for j in [0,2,4]];vol=np.frombuffer(stats[6:8].tobytes(),dtype='<f4').astype('f8')
  source=float(control[22]-control0[22]);sink=float(control[23]-control0[23]);water_error=float(h[~obstacle].sum()*area-water0-source+sink);solid_error=float((sand+sed).sum()*area-solid0)
  # Pre-edit baseline is retained as input, but the long interval begins after the edit.
  if not (s['label']=='initial' and base['label']=='edited'):
   if abs(water_error)>max(.005*water0,1e-8):fail.append('water closure:'+s['label'])
   if abs(solid_error)>max(.01*solid0,1e-9):fail.append('sand+sediment closure:'+s['label'])
  rows.append({'label':s['label'],'time_s':s['advanced_time_s'],'completed_tick':tick,'monitor_tick_count':ticks,'monitor_flags':flags,'all_completed_tick_max_h_drift_m':drift,'water_relative_error':abs(water_error)/water0,'solid_relative_error':abs(solid_error)/solid0,'water_source_m3':source,'water_sink_m3':sink,'cumulative_water_roundoff_cells':counts[0],'cumulative_sediment_roundoff_cells':counts[1],'cumulative_velocity_limit_cells':counts[2],'cumulative_RK_weighted_water_roundoff_m3':float(vol[0]),'cumulative_RK_weighted_sediment_roundoff_m3':float(vol[1])})
 if r['outcome']!='pass' or r['source_drift'] or not all(c['pass'] for c in r['checks']):fail.append('probe failed')
 if full and (r['requested_time_s']!=300 or not rows or abs(rows[-1]['time_s']-300)>.0002):fail.append('not complete five minutes')
 # Numerical recorder ownership must not grow between completed boundaries.
 ownership=r['ownership_samples'];growth=[]
 if ownership:
  first=ownership[0]['counts']
  for s in ownership[1:]:
   if s['counts']!=first:growth.append(s)
 if growth:fail.append('resource ownership growth')
 report={'outcome':'fail' if fail else 'pass','case_id':r['case_id'],'scope':'Full closed-stock five-minute correctness only' if full else 'Short monitor/soak smoke only','failures':fail,'rows':rows,'ownership_growth':growth,'analyzer_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()};return report

def main():
 p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('--full',action='store_true');a=p.parse_args();target=a.folder/'analysis.json'
 if target.exists():raise FileExistsError(target)
 r=analyze(a.folder.resolve(),a.full);target.write_text(json.dumps(r,indent=2));print(json.dumps({'outcome':r['outcome'],'case_id':r['case_id'],'failures':r['failures'],'final':r['rows'][-1] if r['rows'] else None},indent=2));raise SystemExit(r['outcome']!='pass')
if __name__=='__main__':main()
