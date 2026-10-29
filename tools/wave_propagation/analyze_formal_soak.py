"""Audit full-main closed stocks with measured boundary ledger, materials, real Jolt and native recovery."""
import argparse,hashlib,json,math,struct,zipfile
from pathlib import Path
import numpy as np

def analyze(folder,full=False):
 r=json.loads((folder/'diagnosis.json').read_text());fail=[];rows=[];stock0=None;control0=None;generation=None;counts={1:0,2:0,3:0};last_event=-1;age=0.;corrections={};sequence=-1
 def require(ok,message):
  if not ok:fail.append(message)
 with zipfile.ZipFile(folder/'consumed_sources.zip') as z:
  for name,h in r['source_hashes'].items():require(hashlib.sha256(z.read(name.removeprefix('res://'))).hexdigest()==h,'source:'+name)
 require(r['pass'] and r['checks'] and all(c['pass'] for c in r['checks']),'runtime probe');require(len(r['cases'])==1,'one formal case');case=r['cases'][0]
 def raw(s,key):
  item=s['fields'][key];v=Path(item['path']).read_bytes();require(len(v)==item['bytes'] and hashlib.sha256(v).hexdigest()==item['sha256'],'raw:'+s['label']+'/'+key);return v
 def field(s,key,dtype='<f4',channels=1):return np.frombuffer(raw(s,key),dtype=dtype).reshape((256,256,channels) if channels>1 else (256,256)).astype('f8')
 for s in case['snapshots']:
  for key in s['fields']:raw(s,key)
  h=field(s,'water');sand=field(s,'sand');sed=field(s,'sediment');qx=field(s,'momentum_x');qz=field(s,'momentum_z');obs=field(s,'obstacle','u1')>=128;wet=field(s,'wetness','<f2');comp=field(s,'compaction','<f2');support=field(s,'mold_support',channels=2);control=np.frombuffer(raw(s,'control'),dtype='<f4').astype('f8');safety=np.frombuffer(raw(s,'safety'),dtype='<u4')
  require(all(np.isfinite(a).all() for a in [h,sand,sed,qx,qz,wet,comp,support]),'finite:'+s['label']);require(min(h.min(),sand.min(),sed.min())>=0,'nonnegative:'+s['label']);require(wet.min()>=0 and wet.max()<=1 and comp.min()>=0 and comp.max()<=1,'material bounds:'+s['label']);require(np.all((support[:,:,0]>=0)&(support[:,:,0]<=sand)),'support bounds:'+s['label']);tag=support[:,:,0]>0;require(np.array_equal(support[:,:,1][tag],sand[tag]),'support reference:'+s['label']);require(np.all(support[~tag]==0),'empty support:'+s['label'])
  for name in ['sand','sediment','wetness','compaction','mold_support']:require(s['fields'][name]['sha256']==s['fields'][name+'_spare']['sha256'],'spare:'+s['label']+'/'+name)
  require(s['published_matches'],'full publication:'+s['label']);require(int(s['state_seq'])>=sequence,'state sequence:'+s['label']);sequence=int(s['state_seq']);water=float(h[~obs].sum()*.125**2);solid=float((sand+sed).sum()*.125**2)
  if stock0 is None:stock0=(water,solid);control0=control.copy()
  source=float(control[22]-control0[22]);sink=float(control[23]-control0[23]);we=water-stock0[0]-source+sink;se=solid-stock0[1];require(abs(we)<=max(stock0[0]*.005,1e-8),'water ledger closure:'+s['label']);require(abs(se)<=max(stock0[1]*.01,1e-9),'solid closure:'+s['label'])
  item=s['props'];data=Path(item['path']).read_bytes();require(hashlib.sha256(data).hexdigest()==item['sha256'],'props pin:'+s['label']);p=json.loads(data);g=str(p['generation']);q=p['quantum_s'];expected=math.floor((p['water_time_s']-p['origin_time_s']+1e-7)/q)
  if generation!=g:generation=g;counts={1:0,2:0,3:0};last_event=-1
  require(not p['error'] and p['evicted']==0 and not p['holds'],'props status:'+s['label']);require(p['target_steps']==expected and abs(p['admitted_time_s']-expected*q)<1e-7,'physics budget:'+s['label'])
  for event in p['events']:
   require(event['event_id']>last_event,'event order:'+s['label']);last_event=event['event_id'];kind=event['kind'];d=event['data']
   if kind in ['physics','sleep_step']:
    require(str(event['generation'])==g,'old-generation physics:'+s['label']);counts[d['body_id']]+=1
    if kind=='physics':require(not d['error'] and abs(d['state_step']-d['expected_step'])<1e-7,'actual Jolt quantum:'+s['label'])
   if kind=='admit':age=max(age,d['force_age_s']);require(d['force_age_s']<=.150001,'force age:'+s['label'])
  for body in p['bodies']:require(counts[body['body_id']]==expected and round(body['actual_time_s']/q)==expected,'observed callback count:'+s['label']+'/'+str(body['body_id']))
  v=s['visuals'];require(v['foam_enabled'] and v['gravel_enabled'] and v['gravel_active_count']>0,'full visual workload:'+s['label']);require(v['gravel_active_count']==v['gravel_visible_count'],'visible gravel count:'+s['label'])
  volumes=np.frombuffer(safety[6:8].tobytes(),dtype='<f4').astype('f8');corrections[g]={'water_roundoff_cells':int(safety[0])+int(safety[1])*2**32,'sediment_roundoff_cells':int(safety[2])+int(safety[3])*2**32,'velocity_limit_cells':int(safety[4])+int(safety[5])*2**32,'water_roundoff_m3':float(volumes[0]),'sediment_roundoff_m3':float(volumes[1])};rows.append({'label':s['label'],'time_s':s['time_s'],'generation':g,'water_m3':water,'sand_plus_sediment_m3':solid,'water_source_m3':source,'water_sink_m3':sink,'water_error_m3':we,'water_relative_error_initial':abs(we)/stock0[0],'water_relative_error_initial_plus_sources':abs(we)/(stock0[0]+max(0.,source)),'solid_error_m3':se,'solid_relative_error':abs(se)/stock0[1],'physics_steps':expected,'gravel_visible':v['gravel_visible_count']})
 for phase in ['first_edit','second_edit']:
  term=case[phase]['terminals'];positive=[x for x in term if x.get('profile_version',0)>0];require(positive and all(x.get('error_code',0)==0 and x.get('outcome') in [1,2] for x in positive),'actual edit:'+phase)
 growth=[];groups={}
 for record in case['ownership']:
  g=str(record['generation'])
  if g not in groups:groups[g]=record['counts']
  if groups[g]!=record['counts']:growth.append(record)
 require(not growth,'per-generation RID growth');native=json.loads((folder/'independent_native_audit.json').read_text());require(native['outcome']=='pass' and all(c['pass'] for c in native['checks']),'independent native restore')
 require(rows[-1]['time_s']>=r['requested_time_s']-.0001,'final actual time')
 if full:require(r['requested_time_s']==300 and len([s for s in case['snapshots'] if s['label'].startswith('second_')])==300,'complete300s sampling')
 return {'outcome':'fail' if fail else 'pass','scope':'Formal-main five-minute correctness' if full else 'Formal-main short smoke','failures':fail,'rows':rows,'maximum_force_age_s':age,'per_generation_cumulative_roundoff':corrections,'ownership_growth':growth,'resource_samples':case['ownership'],'body_layout':case['body_layout'],'analyzer_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'limitations':'Diagnostic manual completed-time pacing and readbacks are not realtime performance. Actual body layout is the authored default. Native recovery resets nonserialized bodies according to existing policy.'}
def main():
 p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('--full',action='store_true');a=p.parse_args();f=a.folder/'analysis.json'
 if f.exists():raise FileExistsError(f)
 r=analyze(a.folder.resolve(),a.full);f.write_text(json.dumps(r,indent=2));print(json.dumps({'outcome':r['outcome'],'failures':r['failures'],'final':r['rows'][-1] if r['rows'] else None,'maximum_force_age_s':r['maximum_force_age_s']},indent=2));raise SystemExit(r['outcome']!='pass')
if __name__=='__main__':main()
