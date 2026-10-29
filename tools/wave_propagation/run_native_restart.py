"""Separate actual GPU seed/resume processes, then strict native comparison."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import zipfile
from run_lifecycle_case import ENGINE
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--runtime',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();runtime=a.runtime.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);rows=[]
    scripts=['native_restart_probe.gd','compare_native_restart.gd']
    for name in scripts:(out/name).write_bytes((runtime/'tools/wave_propagation'/name).read_bytes())
    for mode in ('seed','resume'):
        directory=out/mode;directory.mkdir();command=[ENGINE,'--path',str(runtime),'--rendering-driver','d3d12','--script','res://tools/wave_propagation/native_restart_probe.gd','--','--output='+str(directory/'data'),'--mode='+mode]
        if mode=='resume':command.append('--input='+str(out/'seed/data/seed.sandue'))
        started=time.time();row={'mode':mode,'command':command,'outcome':'running'};rows.append(row)
        with (directory/'stdout.txt').open('w',encoding='utf-8') as log:
            child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT);row['pid']=child.pid;(out/'status.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
            try:row['exit_code']=child.wait(timeout=300)
            except subprocess.TimeoutExpired:child.terminate();row['exit_code']=child.wait();row['timeout']=True
        row['elapsed_wall_s']=time.time()-started;report=directory/'data/result.json'
        if not report.exists():row['outcome']='incomplete';break
        r=json.loads(report.read_text(encoding='utf-8'));row['outcome']='pass' if row['exit_code']==0 and r['outcome']=='pass' and not r['source_drift'] else 'fail'
        with zipfile.ZipFile(directory/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as archive:
            for name,h in r['configuration']['sources'].items():
                raw=(runtime/name.removeprefix('res://')).read_bytes()
                if hashlib.sha256(raw).hexdigest()!=h:row['outcome']='fail'
                archive.writestr(name.removeprefix('res://'),raw)
        print('NATIVE_RESTART',mode,row['outcome'],flush=True)
        if row['outcome']!='pass':break
    okay=len(rows)==2 and all(r['outcome']=='pass' for r in rows)
    if okay:
        command=[ENGINE,'--headless','--path',str(runtime),'--script','res://tools/wave_propagation/compare_native_restart.gd','--',str(out)]
        with (out/'comparison_stdout.txt').open('w',encoding='utf-8') as log:child=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=120)
        okay=child.returncode==0 and (out/'comparison.json').exists() and json.loads((out/'comparison.json').read_text())['outcome']=='pass'
    report={'schema':1,'outcome':'pass' if okay else 'fail','rows':rows,'scope':'Native cold restart with active wave, coupled material and both visual histories. No prop or scene switching assertion.'}
    (out/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2));raise SystemExit(not okay)
if __name__=='__main__':main()
