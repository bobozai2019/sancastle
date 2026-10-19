"""Serial visible-window lab validation. Never launches concurrent GPU probes."""
import argparse,hashlib,json,subprocess,time,shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
GODOT=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
OUT=ROOT/'test_output/water_momentum_lab'
def identity(p):return {'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def sources():
 paths=[ROOT/'project.godot',ROOT/'scenes/experiments/water_momentum_lab.tscn']
 for base in ['tests/water_momentum_lab','tools/water_momentum_lab']:
  paths += [p for p in (ROOT/base).rglob('*') if p.is_file() and p.suffix not in ['.pyc']]
 return sorted(set(paths))
def run(name,kind,grid=256):
 folder=OUT/name;folder.mkdir(exist_ok=False)
 src=sources();before=[identity(p) for p in src]
 for p in src:
  target=folder/'sources'/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
 args=[str(GODOT),'--path',str(ROOT),'res://scenes/experiments/water_momentum_lab.tscn','--log-file',str(folder/'godot.log'),'--',f'--lab-auto={kind}',f'--lab-grid={grid}',f'--lab-out=res://test_output/water_momentum_lab/{name}']
 manifest={'command':args,'source_before':before,'started_unix':time.time(),'mode':kind,'grid':grid,'window_requested':'visible 1280x720 VSync1','other_gpu_probes':'none launched by this driver; external load not controlled'}
 (OUT/'validation_progress.json').write_text(json.dumps({'active':name,'manifest':manifest},indent=2))
 startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=1
 proc=subprocess.Popen(args,cwd=ROOT,startupinfo=startup)
 manifest['pid']=proc.pid
 try:manifest['exit_code']=proc.wait(timeout=900)
 except subprocess.TimeoutExpired:
  proc.terminate();manifest['aborted']='900s watchdog; GPU release unproven';manifest['exit_code']=proc.wait()
 manifest['ended_unix']=time.time();manifest['source_after']=[identity(p) for p in src]
 manifest['source_unchanged']=manifest['source_before']==manifest['source_after']
 manifest['outputs']=[identity(p) for p in folder.iterdir() if p.is_file()]
 (folder/'manifest.json').write_text(json.dumps(manifest,indent=2))
 print(name,manifest['exit_code'],flush=True)
 return manifest

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--phase',choices=['short','long','all','revised'],default='all');parser.add_argument('--suffix',default='');opts=parser.parse_args()
 jobs=[]
 if opts.phase in ['short','all','revised']:
  jobs += [('numeric64_final','numeric',64),('numeric256_final','numeric',256),('visual_final','visual',256)]
  if opts.phase!='revised':jobs += [(f'lifecycle_{i:02d}','lifecycle',64) for i in range(10)]
 if opts.phase in ['long','all','revised']:
  jobs += [('cost_low_final','cost',256),('cost_detail_final','cost_detail',256),('soak_repeat_final','soak_repeat',256),('soak_sweep_final','soak_sweep',256)]
 results=[]
 for name,kind,grid in jobs:
  name+=opts.suffix
  r=run(name,kind,grid);results.append({'name':name,'exit_code':r['exit_code'],'source_unchanged':r['source_unchanged']})
  log=(OUT/name/'godot.log').read_text(encoding='utf-8',errors='replace')
  if r['exit_code']!=0 or 'SCRIPT ERROR' in log or '\nERROR:' in log or '\nFAIL ' in log:break
 (OUT/f'validation_{opts.phase}{opts.suffix}_summary.json').write_text(json.dumps(results,indent=2))
 (OUT/'validation_progress.json').write_text(json.dumps({'active':None,'completed':results},indent=2))
