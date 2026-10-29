"""Encode captures at their five-frames-per-simulation-second cadence."""
import argparse
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--gate',choices=['G0','G2','G3'],required=True)
parser.add_argument('--run-id',required=True)
parser.add_argument('--ffmpeg',type=Path,required=True)
args=parser.parse_args()
run=ROOT/'task/water_foam_visual/验收'/args.gate/args.run_id
for folder in sorted(run.iterdir()):
    if not folder.is_dir() or not all((folder/f'natural_{i:03d}.png').exists() for i in range(121)):continue
    video=folder/'natural_simulation_time.mp4'
    if video.exists():continue
    cmd=[str(args.ffmpeg),'-framerate','5','-i',str(folder/'natural_%03d.png'),'-frames:v','121','-c:v','libx264','-crf','18','-pix_fmt','yuv420p',str(video)]
    subprocess.run(cmd,check=True,capture_output=True)
    video.with_suffix('.json').write_text(json.dumps({'command':cmd,'frames':121,'fps':5,'source_time_s':[0,24],'note':'Completed simulation time axis; not wall-clock performance footage.'},ensure_ascii=False,indent=2),encoding='utf-8')
    print(video,flush=True)
