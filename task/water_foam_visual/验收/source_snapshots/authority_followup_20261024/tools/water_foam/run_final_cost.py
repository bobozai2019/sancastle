"""Visible A/A then A-B-B-A. Records raw data; never changes production files."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
ENGINE='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'

def identities():
    paths=[]
    for folder,pattern in [('scripts','*.gd'),('scripts','*.glsl'),('shaders','*.glsl'),('assets','*.gdshader'),('scenes','*.tscn'),('assets/unified_edit/presentation','*.json')]:
        paths.extend((ROOT/folder).rglob(pattern))
    paths.extend(ROOT/p for p in ['project.godot','assets/parameters/catalog.json','assets/water_foam/foam_detail.png','assets/water_foam/foam_detail.png.import','tools/water_foam/g0_timing.gd'])
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id',required=True)
    parser.add_argument('--scene',choices=['main','test1_geometry'])
    parser.add_argument('--height',type=int,choices=[720,1080])
    args=parser.parse_args()
    out=ROOT/'task/water_foam_visual/验收/G5'/args.run_id
    out.mkdir(parents=True,exist_ok=False);(out/'.gdignore').touch()
    for scene in [args.scene] if args.scene else ['main','test1_geometry']:
        for height in [args.height] if args.height else [720,1080]:
            for label in ['A1','A2','B1','B2','A3']:
                dest=out/f'{scene}_{height}_{label}';dest.mkdir()
                cmd=[ENGINE,'--path',str(ROOT),'--script','res://tools/water_foam/g0_timing.gd','--',f'--scene=res://scenes/{"main.tscn" if scene=="main" else "playable/test1_geometry.tscn"}', '--output=res://'+dest.relative_to(ROOT).as_posix(),'--ignore-parameter-config']
                if height==1080:cmd.append('--1080p')
                if label.startswith('A'):cmd.append('--foam-baseline')
                before=identities()
                (dest/'command.json').write_text(json.dumps(cmd,ensure_ascii=False,indent=2),encoding='utf-8')
                (dest/'sources_before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
                with (dest/'stdout.log').open('wb') as stdout,(dest/'stderr.log').open('wb') as stderr:
                    try:
                        proc=subprocess.run(cmd,cwd=ROOT,stdout=stdout,stderr=stderr,timeout=300)
                        result={'exit_code':proc.returncode,'timeout':False}
                    except subprocess.TimeoutExpired:result={'exit_code':None,'timeout':True}
                after=identities()
                (dest/'sources_after.json').write_text(json.dumps(after,indent=2),encoding='utf-8')
                result['source_drift']=[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)]
                result['fatal_log']=any(token in (dest/'stderr.log').read_text('utf-8',errors='replace') for token in ['ERROR:','SCRIPT ERROR:','were leaked','still in use'])
                (dest/'result.json').write_text(json.dumps(result),encoding='utf-8')
                print(dest.name,result,flush=True)
                if result['exit_code']!=0 or result['source_drift'] or result['fatal_log']:raise SystemExit(1)

if __name__=='__main__':main()
