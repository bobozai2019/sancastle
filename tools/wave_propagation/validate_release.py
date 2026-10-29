"""Serialize default boot, exact historical sources and real algorithm rollback."""
import argparse,hashlib,json,msvcrt,subprocess,sys,time,zipfile
from pathlib import Path
from run_lifecycle_case import ENGINE

def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--resume-from',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];out=a.output.resolve();lock=(root/'test_output/wave_propagation/experience_gpu.lock').open('a+b');lock.seek(0)
 try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
 except OSError:raise SystemExit('GPU probe active; release validation not started')
 out.mkdir(parents=True,exist_ok=False);(out/'coordinator.py').write_bytes(Path(__file__).read_bytes());state={'outcome':'running','completed':[],'started_wall_s':time.time()}
 def write():(out/'state.json').write_text(json.dumps(state,indent=2))
 def run(name,cmd,report,boolean=False,timeout=900):
  state['current']=name;write();print('RELEASE_START',name,flush=True)
  with (out/(name+'.stdout.txt')).open('w',encoding='utf-8') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=timeout)
  r=json.loads(report.read_text());okay=r.get('pass',False) if boolean else r.get('outcome')=='pass'
  if not okay or not r.get('checks') or not all(c['pass'] if 'pass' in c else c.get('ready') and c.get('released') for c in r['checks']):raise RuntimeError('Release report failed: '+name)
  state['completed'].append(name);write();print('RELEASE_TERMINAL',name,flush=True)
 def gd(script,args,headless=False):return [ENGINE,*(['--headless'] if headless else []),'--path',str(root),*([] if headless else ['--rendering-driver','d3d12']),'--script','res://tools/wave_propagation/'+script,'--',*args]
 try:
  prior_run=a.resume_from.resolve() if a.resume_from else None
  if prior_run:
   previous=json.loads((prior_run/'state.json').read_text())
   if previous['outcome']!='fail' or previous['completed']!=['default_boot','offline_migration','restore_main'] or previous['current']!='audit_main':raise RuntimeError('Unexpected resume boundary')
   boot=prior_run/'default_boot';state['reused_artifacts']=[]
   for name,path in [('default_boot',boot/'result.json'),('offline_migration',prior_run/'offline_migration.json'),('restore_main',prior_run/'restore_main/probe.json')]:
    report=json.loads(path.read_text())
    if not (report.get('pass',False) if name=='restore_main' else report.get('outcome')=='pass'):raise RuntimeError('Reused report failed: '+name)
    state['completed'].append(name);state['reused_artifacts'].append({'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
   with zipfile.ZipFile(prior_run/'restore_main/consumed_sources.zip') as z:
    for name,h in json.loads((prior_run/'restore_main/probe.json').read_text())['observations']['sources'].items():
     raw=(root/name.removeprefix('res://')).read_bytes()
     if hashlib.sha256(raw).hexdigest()!=h or z.read(name.removeprefix('res://'))!=raw:raise RuntimeError('Reused production sources changed: '+name)
   write()
  else:
   boot=out/'default_boot';run('default_boot',gd('gather_release_configurations.gd',['--output='+str(boot),'--use-default','--save-checkpoints']),boot/'result.json')
   run('offline_migration',gd('numerics_migration_probe.gd',['--output='+str(out/'offline_migration.json'),'--targets='+str(boot/'targets.variant')],True),out/'offline_migration.json')
  prior=json.loads((root/'test_output/wave_propagation/g4_source_restore_02/fixtures.json').read_text());pins=json.loads((root/'test_output/wave_propagation/g6_release_prepare_01/release_pins.json').read_text());groups={'main':prior,'test1_capture':[],'test1_backwash':[],'test1_geometry':[]}
  for pin in pins:
   raw_path=pin['path'].removeprefix('res://');path=root/raw_path;row={'path':str(path),'sha256':pin['sha256'],'origin':'original_available'};key=next((k for k in ['test1_capture','test1_backwash','test1_geometry'] if 'formal_'+k+'_' in path.name),'main');groups[key].append(row)
  run_folders={}
  for key,fixtures in groups.items():
   source=out/(key+'_fixtures.json');source.write_text(json.dumps(fixtures,indent=2));folder=prior_run/'restore_main' if prior_run and key=='main' else out/('restore_'+key);run_folders[key]=folder
   if not (prior_run and key=='main'):
    cmd=[sys.executable,str(root/'tools/wave_propagation/run_source_restore.py'),'--runtime',str(root),'--fixtures',str(source),'--output',str(folder),'--scene',key,'--matched-domain'];run('restore_'+key,cmd,folder/'probe.json',True)
   run('audit_'+key,gd('audit_source_restore.gd',[str(folder),str(len(fixtures))],True),folder/'independent_audit_release.json')
  switch=out/'algorithm_switch';switch.mkdir();run('algorithm_switch',gd('numerics_switch_probe.gd',['--output='+str(switch)]),switch/'probe.json',True)
  run('audit_algorithm_switch',gd('audit_algorithm_switch.gd',[str(switch)],True),switch/'independent_audit.json')
  sources={}
  # Gather's binary has exact configs; boot and migration reports plus each
  # actual restore archive retain their own source identities independently.
  for key in groups:
   r=json.loads((run_folders[key]/'probe.json').read_text());sources.update(r['observations']['sources'])
  with zipfile.ZipFile(out/'release_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
   for name,h in sources.items():
    raw=(root/name.removeprefix('res://')).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=h:raise RuntimeError('Release source drift: '+name)
    z.writestr(name.removeprefix('res://'),raw)
  state['outcome']='pass';state['current']=None
 except Exception as e:state['outcome']='fail';state['error']=repr(e);raise
 finally:state['finished_wall_s']=time.time();write()
if __name__=='__main__':main()
