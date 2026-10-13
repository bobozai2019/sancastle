"""Supervise one owned visible Godot process; return its actual exit and artifacts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import shutil

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--output',required=True,type=Path)
parser.add_argument('--scene',required=True)
parser.add_argument('--script',default='res://tests/water_material_natural/capture.gd')
parser.add_argument('--tick',default=360,type=int)
parser.add_argument('--lighting-ablation',action='store_true')
parser.add_argument('--allowed-godot-pid',action='append',type=int,default=[])
parser.add_argument('--exclusive',action='store_true')
parser.add_argument('--init-timeout-s',type=int,default=180)
parser.add_argument('--resolution',default='1280x720',choices=['1280x720','1920x1080'])
parser.add_argument('--borderless',action='store_true')
parser.add_argument('--checkpoint',type=Path)
args=parser.parse_args()
from process_watch import godot_processes
initial_processes=godot_processes()
allowed=set(args.allowed_godot_pid)
if args.exclusive and any(p['pid'] not in allowed for p in initial_processes):
    raise RuntimeError('Other Godot process active; refusing a concurrent performance probe: '+json.dumps(initial_processes))
out=args.output.resolve()
out.mkdir(parents=True,exist_ok=False)
sources=[]
for directory in ('assets/water_material_natural_candidate','scenes/water_material_natural_candidate','tests/water_material_natural'):
    sources.extend(p for p in (ROOT/directory).iterdir() if p.is_file() and not p.name.endswith('.uid'))
sources.extend(ROOT/p for p in ('assets/test1_beach/test1_beach_release.json','assets/test1_beach/test1_water_front.gdshader',
                               'assets/test1_beach/test1_front_foam_splats.gdshader','assets/test1_beach/test1_bed_lit_fast.gdshader',
                               'scripts/visual/test1_beach_fixed_entry.gd','scripts/visual/water_render_staging_entry.gd',
                               'scenes/sandcastle_test1_beach_fixed.tscn','scenes/sandcastle_test1_beach_coupled.tscn'))
source_index=[]
for source in sources:
    target=out/'source_snapshot'/(str(source.relative_to(ROOT))+'.source')
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(source,target)
    source_index.append({'path':str(source),'snapshot':str(target),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
(out/'source_index.json').write_text(json.dumps(source_index,indent=2),encoding='utf-8')
command=['D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe',
         '--path',str(ROOT),'--rendering-driver','d3d12','--resolution',args.resolution,'--disable-vsync',
         '--log-file',str(out/'godot.log'),'--script',args.script,'--',
         '--scene='+args.scene,'--output='+str(out),'--tick='+str(args.tick),
         '--init-timeout-s='+str(args.init_timeout_s)]
if args.lighting_ablation:command+=['--lighting-ablation']
if args.checkpoint:command+=['--checkpoint='+str(args.checkpoint.resolve())]
if args.borderless:
    position=command.index('--')
    command[position:position]=['--borderless','--position','0,0']
started=time.time()
process=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
(out/'owner.json').write_text(json.dumps({'pid':process.pid,'command':command,'started_unix':started},indent=2))
observations=[]
conflict_aborted=False
while True:
    observed=godot_processes()
    others=[p for p in observed if p['pid'] not in allowed and p['pid']!=process.pid]
    observations.append({'unix':time.time(),'others':others})
    if args.exclusive and others:
        conflict_aborted=True
        process.terminate()
        code=process.wait(timeout=30)
        break
    try:
        code=process.wait(timeout=.25)
        break
    except subprocess.TimeoutExpired:
        pass
result={'exit_code':code,'elapsed_s':time.time()-started,'pid':process.pid,'command':command,
        'logs':{'path':str(out/'godot.log'),'sha256':hashlib.sha256((out/'godot.log').read_bytes()).hexdigest()},
        'artifact_operation_complete':code==0 and (out/'manifest.json').is_file(),
        'scope':'process/operation status only; gates require separate review'}
result['sources_unchanged_during_run']=all(hashlib.sha256(Path(s['path']).read_bytes()).hexdigest()==s['sha256'] for s in source_index)
result['engine_errors']=[line.strip() for line in (out/'godot.log').read_text(encoding='utf-8',errors='replace').splitlines()
                         if line.startswith(('ERROR:','SCRIPT ERROR:','SHADER ERROR:'))]
result['engine_error_free']=not result['engine_errors']
result['artifact_operation_complete']=result['artifact_operation_complete'] and result['engine_error_free']
result['initial_godot_processes']=initial_processes
result['allowed_godot_pids']=sorted(allowed)
result['exclusive_requested']=args.exclusive
result['concurrent_godot_detected']=any(o['others'] for o in observations)
result['exclusive_conflict_aborted']=conflict_aborted
(out/'process_observations.json').write_text(json.dumps(observations,indent=2),encoding='utf-8')
(out/'process_result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
raise SystemExit(code)
