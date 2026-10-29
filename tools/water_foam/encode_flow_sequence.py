"""Encode actual captured frames on their simulation-time axis."""
import argparse
import json
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--run-id',required=True)
parser.add_argument('--ffmpeg',type=Path,required=True)
args=parser.parse_args()
run=ROOT/'task/water_foam_visual/验收/G2'/args.run_id
for directory in sorted(run.iterdir()):
    if not directory.is_dir():continue
    for name in ['positive','negative']:
        if not all((directory/f'flow_{name}_{i:03d}.png').exists() for i in range(81)):continue
        video=directory/f'flow_{name}_simulation_time.mp4'
        if video.exists():continue
        cmd=[str(args.ffmpeg),'-y','-framerate','10','-i',str(directory/f'flow_{name}_%03d.png'),'-frames:v','81','-c:v','libx264','-crf','18','-pix_fmt','yuv420p',str(video)]
        subprocess.run(cmd,check=True,capture_output=True)
        video.with_suffix('.json').write_text(json.dumps(dict(command=cmd,frames=81,fps=10,source_time_s=[0,8],note='Material diagnostic sequence on simulation-time axis; not real-time performance footage'),indent=2),encoding='utf-8')
        print(video)
