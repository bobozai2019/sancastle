"""Run one isolated GPU numeric case and retain a terminal process/result record."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import time

ENGINE=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
CASES=['lake_flat','lake_slope','lake_step','lake_shore','lake_obstacle','wave_0.5m','wave_1m','wave_2m','wave_4m','wave_z_2m','wave_diagonal_2m','dam_break','near_dry','cfl_capacity','concentration_001','concentration_005']
SPECIAL_CASES=['negative','nonfinite','obstacle_pulse','velocity_cap','strong_shovel']
COUPLING_CASES=['erosion','deposition','transport_forward','transport_backward','constant_001_off','constant_005_off','reversal','near_dry','obstacle','boundary','support','molded_edit']


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--project-root',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--solver',choices=['rusanov_first_order_v1','muscl_mc_ssprk2_v1'],required=True)
    ap.add_argument('--case',choices=sorted(set(CASES+SPECIAL_CASES+COUPLING_CASES)),required=True)
    ap.add_argument('--suite',choices=['water','coupling'],default='water')
    ap.add_argument('--duration',type=float,default=.1)
    ap.add_argument('--tick-dt',type=float,default=1/30)
    ap.add_argument('--depth',type=float,default=.1)
    ap.add_argument('--amplitude',type=float,default=.0001)
    args=ap.parse_args()
    if not math.isfinite(args.duration) or not 0<args.duration<=6 or not math.isfinite(args.tick_dt) or not 0<args.tick_dt<=1/30+1e-9:
        ap.error('invalid duration/tick-dt')
    if not math.isfinite(args.depth) or not .005<=args.depth<=1 or not math.isfinite(args.amplitude) or not 0<args.amplitude<=.01:ap.error('invalid depth/amplitude')
    if args.suite=='coupling':
        if args.case not in COUPLING_CASES or args.depth!=.1 or args.amplitude!=.0001:ap.error('unsupported coupling preset/override')
        if args.solver!='muscl_mc_ssprk2_v1' and (args.case.endswith('_off') or args.case=='reversal'):ap.error('stage-only transport fixture requires MUSCL')
    elif args.case not in CASES+SPECIAL_CASES:ap.error('case requires coupling suite')
    runtime=args.project_root.resolve();out=args.output.resolve()
    if not (runtime/'project.godot').is_file():ap.error('missing project')
    out.mkdir(parents=True,exist_ok=False)
    script='coupling_gpu_probe.gd' if args.suite=='coupling' else ('special_gpu_probe.gd' if args.case in SPECIAL_CASES else 'gpu_probe.gd')
    probe=runtime/'tools/wave_propagation'/script
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    (out/'probe.gd').write_bytes(probe.read_bytes())
    command=[str(ENGINE),'--path',str(runtime),'--rendering-driver','d3d12','--script','res://tools/wave_propagation/'+script,
             '--log-file',str(out/'godot.log'),'--','--output='+str(out),'--solver='+args.solver,'--case='+args.case,
             '--duration='+str(args.duration),'--tick-dt='+str(args.tick_dt),'--depth='+str(args.depth),'--amplitude='+str(args.amplitude)]
    manifest={'command':command,'started_unix':time.time(),'engine_sha256':digest(ENGINE),'probe_sha256':digest(probe),
              'scope':'Numerical GPU verification, no performance measurement','outcome':'running'}
    with (out/'stdout.txt').open('w',encoding='utf-8') as log:
        process=subprocess.Popen(command,cwd=runtime,stdout=log,stderr=subprocess.STDOUT)
        manifest['pid']=process.pid
        (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
        try:
            manifest['exit_code']=process.wait(timeout=630)
        except subprocess.TimeoutExpired:
            process.terminate();manifest['exit_code']=process.wait();manifest['timeout']=True
    manifest['elapsed_wall_s']=time.time()-manifest['started_unix']
    manifest['outcome']='incomplete'
    if (out/'result.json').is_file():
        result=json.loads((out/'result.json').read_text(encoding='utf-8'))
        manifest['outcome']=result.get('outcome','incomplete')
    if manifest['exit_code'] or digest(probe)!=manifest['probe_sha256']:manifest['outcome']='fail'
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(manifest,indent=2));print((out/'stdout.txt').read_text(encoding='utf-8',errors='replace')[-6000:])
    raise SystemExit(manifest['outcome']!='pass')


if __name__=='__main__':main()
