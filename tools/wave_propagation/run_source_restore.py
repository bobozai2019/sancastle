"""Run pinned old/rebuilt sources through the actual formal MC restore route."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import zipfile
from run_lifecycle_case import ENGINE
def main():
    p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--fixtures',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--scene',choices=['main','test1_capture','test1_backwash','test1_geometry'],default='main');a=p.parse_args();runtime=a.runtime.resolve();out=a.output.resolve();fixtures=json.loads(a.fixtures.read_text(encoding='utf-8'))
    if not isinstance(fixtures,list) or not 1<=len(fixtures)<=16:raise ValueError('invalid fixtures')
    for item in fixtures:
        file=Path(item['path'])
        if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=item['sha256']:raise ValueError('source fixture identity')
    out.mkdir(parents=True,exist_ok=False);(out/'fixtures.json').write_bytes(a.fixtures.read_bytes());script=runtime/'tools/wave_propagation/native_source_restore_probe.gd';(out/'probe.gd').write_bytes(script.read_bytes());(out/Path(__file__).name).write_bytes(Path(__file__).read_bytes())
    command=[ENGINE,'--path',str(runtime),'--rendering-driver','d3d12','--script','res://tools/wave_propagation/native_source_restore_probe.gd','--','--output='+str(out),'--fixtures='+str(out/'fixtures.json'),'--scene='+a.scene]
    manifest={'command':command,'outcome':'running','probe_sha256':hashlib.sha256(script.read_bytes()).hexdigest(),'engine_sha256':hashlib.sha256(Path(ENGINE).read_bytes()).hexdigest(),'scope':'Functional full-source migration, raw GPU resave and continuation; no performance measurement'};started=time.time()
    with (out/'stdout.txt').open('w',encoding='utf-8') as log:
        child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT);manifest['pid']=child.pid;(out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
        try:manifest['exit_code']=child.wait(timeout=600)
        except subprocess.TimeoutExpired:child.terminate();manifest['exit_code']=child.wait();manifest['timeout']=True
    manifest['elapsed_wall_s']=time.time()-started;manifest['outcome']='incomplete';report=out/'probe.json'
    if report.exists():
        r=json.loads(report.read_text(encoding='utf-8'));manifest['outcome']='pass' if r['pass'] and r['checks'] and all(row['pass'] for row in r['checks']) else 'fail';drift=[]
        with zipfile.ZipFile(out/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
            for name,h in r['observations']['sources'].items():
                raw=(runtime/name.removeprefix('res://')).read_bytes()
                if hashlib.sha256(raw).hexdigest()!=h:drift.append(name)
                z.writestr(name.removeprefix('res://'),raw)
        manifest['source_drift']=drift
        if drift:manifest['outcome']='fail'
    if manifest['exit_code'] or hashlib.sha256(script.read_bytes()).hexdigest()!=manifest['probe_sha256']:manifest['outcome']='fail'
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print(json.dumps(manifest,indent=2));print((out/'stdout.txt').read_text(encoding='utf-8',errors='replace')[-3500:]);raise SystemExit(manifest['outcome']!='pass')
if __name__=='__main__':main()
