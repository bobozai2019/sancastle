"""Strict serial single-case launcher for prepared G4 tests."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
ENGINE='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
CASES={'restore':['normal','restore_distinct','restore_hold','restore_cancel','restore_registration','restore_corrupt','restore_unknown','restore_cohesion'],
       'initialization':['init_water','init_coupled','init_unknown','init_compile'],
       'checkpoint':['normal','checkpoint_queued','checkpoint_recorded','checkpoint_physics','checkpoint_readback'],
       'formal_final':['boot_main','restoreclose_main','faultrestore_main','faultclose_main','detach_main'],
       'formal_boundary':['capture_main','height_main','physics_main','recorded_main'],
       'reader':['normal'],'formal_candidate':['main'],'formal_service':['main']}
def main():
    p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--kind',choices=CASES,required=True);p.add_argument('--case',required=True);a=p.parse_args()
    if a.case not in CASES[a.kind]:p.error('unknown case')
    runtime=a.runtime.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);script=runtime/'tools/wave_propagation/g4_generated'/(a.kind+'.gd')
    preparation=json.loads((script.parent/'preparation.json').read_text(encoding='utf-8'));row=next(r for r in preparation['rows'] if r['name']==a.kind)
    digest=lambda file:hashlib.sha256(file.read_bytes()).hexdigest()
    if digest(script)!=row['generated_sha256']:raise ValueError('prepared probe identity')
    report=out/('probe.json' if a.kind.startswith('formal_') else 'result.json')
    output=out if a.kind.startswith('formal_') else report
    args=['--scene='+a.case] if a.kind.startswith('formal_') else ['--case='+a.case]
    command=[ENGINE,'--path',str(runtime),'--rendering-driver','d3d12','--script','res://'+script.relative_to(runtime).as_posix(),'--','--output='+str(output),*args]
    started=time.time();manifest={'command':command,'outcome':'running','probe_sha256':digest(script),'engine_sha256':digest(Path(ENGINE)),'scope':'G4 functional lifecycle, not performance measurement'}
    (out/'probe.gd').write_bytes(script.read_bytes());(out/'preparation.json').write_text(json.dumps(preparation,indent=2),encoding='utf-8')
    with (out/'stdout.txt').open('w',encoding='utf-8') as log:
        child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,cwd=runtime);manifest['pid']=child.pid;(out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
        try:code=child.wait(timeout=360)
        except subprocess.TimeoutExpired:child.terminate();code=child.wait();manifest['timeout']=True
    manifest.update(exit_code=code,elapsed_wall_s=time.time()-started,outcome='incomplete')
    if report.exists():
        result=json.loads(report.read_text(encoding='utf-8'));manifest['outcome']='pass' if result.get('pass',False) and result.get('checks') and all(c['pass'] for c in result['checks']) else 'fail'
    if code or digest(script)!=manifest['probe_sha256']:manifest['outcome']='fail'
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print(json.dumps(manifest,indent=2));print((out/'stdout.txt').read_text(encoding='utf-8',errors='replace')[-2500:]);raise SystemExit(manifest['outcome']!='pass')
if __name__=='__main__':main()
