"""Real Jolt/sample clock regression with an explicit MC water wave fixture."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import zipfile
from run_lifecycle_case import ENGINE
def main():
    p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--case',choices=['flow_positive','delay'],required=True);a=p.parse_args();runtime=a.runtime.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    script=runtime/'tools/wave_propagation/muscl_bottle_clock_probe.gd';(out/'probe.gd').write_bytes(script.read_bytes());(out/'run_bottle_clock.py').write_bytes(Path(__file__).read_bytes())
    command=[ENGINE,'--path',str(runtime),'--rendering-driver','d3d12','--script','res://tools/wave_propagation/muscl_bottle_clock_probe.gd','--','--output='+str(out/'result.json'),'--case='+a.case]
    row={'command':command,'probe_sha256':hashlib.sha256(script.read_bytes()).hexdigest(),'outcome':'running','scope':'Functional GPU sampling and real Jolt clock; no performance measurement'};started=time.time()
    with (out/'stdout.txt').open('w',encoding='utf-8') as log:
        child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT);row['pid']=child.pid;(out/'manifest.json').write_text(json.dumps(row,indent=2),encoding='utf-8')
        try:row['exit_code']=child.wait(timeout=180)
        except subprocess.TimeoutExpired:child.terminate();row['exit_code']=child.wait();row['timeout']=True
    row['elapsed_wall_s']=time.time()-started;row['outcome']='incomplete'
    if (out/'result.json').exists():
        r=json.loads((out/'result.json').read_text(encoding='utf-8'));row['outcome']='pass' if r.get('pass',False) and r['checks'] and all(c['pass'] for c in r['checks']) else 'fail'
        drift=[]
        with zipfile.ZipFile(out/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
            for name,h in r['observations']['sources'].items():
                raw=(runtime/name.removeprefix('res://')).read_bytes()
                if hashlib.sha256(raw).hexdigest()!=h:drift.append(name)
                z.writestr(name.removeprefix('res://'),raw)
        row['source_drift']=drift
        if drift:row['outcome']='fail'
    if row['exit_code'] or hashlib.sha256(script.read_bytes()).hexdigest()!=row['probe_sha256']:row['outcome']='fail'
    (out/'manifest.json').write_text(json.dumps(row,indent=2),encoding='utf-8');print(json.dumps(row,indent=2));print((out/'stdout.txt').read_text(encoding='utf-8',errors='replace')[-2500:]);raise SystemExit(row['outcome']!='pass')
if __name__=='__main__':main()
