"""Bounded 720p splash off/on/on/off comparison. Separate from historical foam Gates."""
import argparse,subprocess,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ENGINE='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
p=argparse.ArgumentParser();p.add_argument('--run-id',required=True);args=p.parse_args()
out=ROOT/'task/shore_splash_visual/验收'/args.run_id
out.mkdir(parents=True,exist_ok=False);(out/'.gdignore').touch()
def identities():
    paths=[q for folder in ['scripts','shaders'] for q in (ROOT/folder).rglob('*') if q.suffix in ['.gd','.glsl','.gdshader']]
    paths += [ROOT/q for q in ['assets/parameters/catalog.json','scenes/parameters/parameter_windows.tscn','tools/water_foam/shore_splash_timing.gd','tools/water_foam/run_shore_splash_cost.py']]
    paths += list((ROOT/'assets/unified_edit/presentation').glob('*.json'))
    paths += [ROOT/'scenes/unified_edit/presentation'/f'{k}.tscn' for k in ['main','test1_geometry']]
    return {q.relative_to(ROOT).as_posix():hashlib.sha256(q.read_bytes()).hexdigest() for q in paths}
def save(dest,name,value):(dest/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),'utf-8')
for scene in ['main','test1_geometry']:
    for label in ['A1','B1','B2','A2']:
        dest=out/(scene+'_'+label);dest.mkdir()
        scene_path='res://scenes/'+('main.tscn' if scene=='main' else 'playable/test1_geometry.tscn')
        cmd=[ENGINE,'--path',str(ROOT),'--script','res://tools/water_foam/shore_splash_timing.gd','--','--scene='+scene_path,'--output=res://'+dest.relative_to(ROOT).as_posix(),'--ignore-parameter-config']
        if label.startswith('A'):cmd.append('--splash-off')
        before=identities();save(dest,'sources_before.json',before);save(dest,'command.json',cmd)
        with (dest/'stdout.log').open('wb') as stdout,(dest/'stderr.log').open('wb') as stderr:
            try:
                result=subprocess.run(cmd,cwd=ROOT,stdout=stdout,stderr=stderr,timeout=240)
                result={'exit_code':result.returncode,'timeout':False}
            except subprocess.TimeoutExpired:result={'exit_code':None,'timeout':True}
        after=identities();save(dest,'sources_after.json',after);result['source_drift']=[n for n in before.keys()|after.keys() if before.get(n)!=after.get(n)]
        result['fatal_log']=any(token in (dest/'stderr.log').read_text('utf-8',errors='replace') for token in ['ERROR:','SCRIPT ERROR:','were leaked','still in use'])
        save(dest,'result.json',result);print(scene,label,result,flush=True)
        if result['exit_code']!=0 or result['timeout'] or result['source_drift'] or result['fatal_log']:raise SystemExit(1)
