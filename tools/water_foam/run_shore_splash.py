"""Run one visible splash probe, serially; preserve immutable source identities."""
import argparse,subprocess,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ENGINE='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
parser=argparse.ArgumentParser();parser.add_argument('--run-id',required=True);parser.add_argument('--scene',default='main',choices=['main','test1_geometry']);parser.add_argument('--off',action='store_true');parser.add_argument('--closeup',action='store_true');parser.add_argument('--probe',default='shore_splash_probe.gd',choices=['shore_splash_probe.gd','shore_splash_fixture_probe.gd'])
args=parser.parse_args()
dest=ROOT/'task/shore_splash_visual/验收'/args.run_id/args.scene
dest.mkdir(parents=True,exist_ok=False);(dest.parent/'.gdignore').touch()
def identities():
    paths=[p for folder in ['scripts','shaders'] for p in (ROOT/folder).rglob('*') if p.suffix in ['.gd','.glsl','.gdshader']]
    paths += [ROOT/p for p in ['scripts/beach/unified_playable_entry.gd','scenes/components/shore_splash.tscn','assets/water_splash/instances.tres','assets/parameters/catalog.json','scenes/parameters/parameter_windows.tscn','tests/visual_water_alignment/'+args.probe,'tools/water_foam/run_shore_splash.py']]
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
def save(name,value):(dest/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),'utf-8')
cmd=[ENGINE,'--path',str(ROOT),'--script','res://tests/visual_water_alignment/'+args.probe,'--','--scene='+args.scene,'--output=res://'+dest.relative_to(ROOT).as_posix(),'--ignore-parameter-config']
if args.off:cmd.append('--splash-off')
if args.closeup:
    cmd.append('--closeup')
    if args.scene=='main':cmd.append('--target=-5.14,0.25,4.11')
before=identities();save('sources_before.json',before);save('command.json',cmd)
with (dest/'stdout.log').open('wb') as stdout,(dest/'stderr.log').open('wb') as stderr:
    try:
        p=subprocess.run(cmd,cwd=ROOT,stdout=stdout,stderr=stderr,timeout=420)
        result={'exit_code':p.returncode,'timeout':False}
    except subprocess.TimeoutExpired:result={'exit_code':None,'timeout':True}
after=identities();save('sources_after.json',after);result['source_drift']=[n for n in before.keys()|after.keys() if before.get(n)!=after.get(n)]
save('result.json',result);print(result,flush=True)
