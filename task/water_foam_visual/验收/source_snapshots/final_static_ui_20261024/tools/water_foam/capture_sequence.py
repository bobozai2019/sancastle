"""Run separately after timing finishes; encode simulation-time video if FFmpeg supplied."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ENGINE='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--ffmpeg',type=Path)
    parser.add_argument('--run-id',required=True)
    args=parser.parse_args()
    run_root=ROOT/'task/water_foam_visual/验收/G0'/args.run_id
    if run_root.exists():raise SystemExit('Evidence directory exists; choose a new run-id')
    for scene in ['main','test1_geometry']:
        dest=run_root/scene
        dest.mkdir(parents=True,exist_ok=True)
        (dest.parent/'.gdignore').touch()
        cmd=[ENGINE,'--path',str(ROOT),'--script','res://tests/visual_water_alignment/foam_visual_probe.gd','--','--scene='+scene,'--output=res://'+dest.relative_to(ROOT).as_posix()]
        (dest/'command.json').write_text(json.dumps(cmd,ensure_ascii=False,indent=2),encoding='utf-8')
        tracked=list((ROOT/'scripts').rglob('*.gd'))+list((ROOT/'scripts').rglob('*.glsl'))+list((ROOT/'assets').rglob('*.gdshader'))+list((ROOT/'scenes').rglob('*.tscn'))+list((ROOT/'assets/unified_edit/presentation').glob('*.json'))
        before={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked}
        (dest/'sources_before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
        with (dest/'stdout.log').open('wb') as out,(dest/'stderr.log').open('wb') as err:
            try:
                result=subprocess.run(cmd,cwd=ROOT,stdout=out,stderr=err,timeout=900)
                outcome={'exit_code':result.returncode,'timeout':False}
            except subprocess.TimeoutExpired:
                outcome={'exit_code':None,'timeout':True}
        after={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked if p.is_file()}
        (dest/'sources_after.json').write_text(json.dumps(after,indent=2),encoding='utf-8')
        outcome['source_drift']=[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)]
        (dest/'result.json').write_text(json.dumps(outcome),encoding='utf-8')
        if outcome['exit_code']!=0 or outcome['source_drift']:raise SystemExit(outcome)
        if args.ffmpeg:
            cmd=[str(args.ffmpeg),'-y','-framerate','10','-i',str(dest/'frame_%04d.png'),'-c:v','libx264','-crf','18','-pix_fmt','yuv420p',str(dest/'baseline_simulation_time.mp4')]
            subprocess.run(cmd,check=True,capture_output=True)
        print(scene,outcome,flush=True)

if __name__=='__main__':main()
