"""Serial A/A baseline, all formal scene/resolution combinations."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ENGINE='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
parser=argparse.ArgumentParser()
parser.add_argument('--run-id',required=True,help='New directory; existing evidence is never overwritten')
parser.add_argument('--scene',choices=['main','test1_geometry'])
parser.add_argument('--height',type=int,choices=[720,1080])
args=parser.parse_args()
OUT=ROOT/'task/water_foam_visual/验收/G0'/args.run_id
if OUT.exists():raise SystemExit('Evidence directory exists; choose a new run-id')
def identities():
    paths=list((ROOT/'scripts').rglob('*.gd'))+list((ROOT/'scripts').rglob('*.glsl'))+list((ROOT/'shaders').rglob('*.glsl'))+list((ROOT/'assets').rglob('*.gdshader'))
    paths+=list((ROOT/'scenes').rglob('*.tscn'))+list((ROOT/'assets/unified_edit/presentation').glob('*.json'))+[ROOT/'assets/parameters/catalog.json',ROOT/'project.godot']
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
for scene in [args.scene] if args.scene else ['main','test1_geometry']:
    for height in [args.height] if args.height else [720,1080]:
        for repeat in [1,2]:
            dest=OUT/f'{scene}_{height}_A{repeat}'
            dest.mkdir(parents=True,exist_ok=True)
            (OUT/'.gdignore').touch()
            cmd=[ENGINE,'--path',str(ROOT),'--script','res://tools/water_foam/g0_timing.gd','--',f'--scene=res://scenes/{"main.tscn" if scene=="main" else "playable/test1_geometry.tscn"}', '--output=res://'+dest.relative_to(ROOT).as_posix()]
            if height==1080:cmd.append('--1080p')
            (dest/'command.json').write_text(json.dumps(cmd,ensure_ascii=False,indent=2),encoding='utf-8')
            before=identities()
            (dest/'sources_before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
            with (dest/'stdout.log').open('wb') as out,(dest/'stderr.log').open('wb') as err:
                try:
                    result=subprocess.run(cmd,cwd=ROOT,stdout=out,stderr=err,timeout=240)
                    outcome={'exit_code':result.returncode,'timeout':False}
                except subprocess.TimeoutExpired:
                    outcome={'exit_code':None,'timeout':True}
            after=identities()
            (dest/'sources_after.json').write_text(json.dumps(after,indent=2),encoding='utf-8')
            outcome['source_drift']=[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)]
            (dest/'result.json').write_text(json.dumps(outcome),encoding='utf-8')
            print(dest.name,outcome,flush=True)
            if outcome['exit_code']!=0 or outcome['source_drift']:raise SystemExit(1)
