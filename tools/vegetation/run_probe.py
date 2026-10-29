"""Run one visible real-GPU vegetation check; retain sources, logs and failed runs."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
import zipfile

ROOT=Path(__file__).resolve().parents[2]
ENGINE=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')


def sha(data):return hashlib.sha256(data).hexdigest()


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--scene',default='main',choices=('main','test1_geometry'))
    p.add_argument('--case',default='smoke',choices=('smoke','behavior','lifecycle','cost','soak','views'))
    p.add_argument('--timeout',type=int,default=240)
    args=p.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    spec=importlib.util.spec_from_file_location('audit',ROOT/'tools/unified_edit_pipeline/audit_architecture.py')
    audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
    sources,_,missing=audit.graph()
    for path in ('tests/vegetation/entry_probe.gd','tests/integration/unified_edit_playable_probe.gd','tools/vegetation/run_probe.py','project.godot'):
        sources[path]=(ROOT/path).read_bytes()
    hashes={name:sha(raw) for name,raw in sources.items()}
    with zipfile.ZipFile(out/'sources.zip','x',zipfile.ZIP_DEFLATED) as z:
        for name,raw in sorted(sources.items()):z.writestr(name,raw)
    command=[str(ENGINE),'--path',str(ROOT),'--rendering-driver','d3d12','--script','res://tests/vegetation/entry_probe.gd',
             '--log-file',str(out/'godot.log'),'--','--output='+str(out),'--scene='+args.scene,'--case='+args.case]
    start=time.time();timed_out=False
    with (out/'stdout.txt').open('wb') as log:
        proc=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        try:code=proc.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out=True;proc.terminate();code=proc.wait(timeout=15)
    report=json.loads((out/'probe.json').read_text(encoding='utf-8-sig')) if (out/'probe.json').exists() else {}
    text=(out/'godot.log').read_text(encoding='utf-8-sig') if (out/'godot.log').exists() else ''
    drift=[name for name,h in hashes.items() if not (ROOT/name).exists() or sha((ROOT/name).read_bytes())!=h]
    result=dict(scene=args.scene,case=args.case,command=command,engine_sha256=sha(ENGINE.read_bytes()),elapsed_s=time.time()-start,
                exit_code=code,timed_out=timed_out,sources=hashes,source_zip_sha256=sha((out/'sources.zip').read_bytes()),
                source_drift=drift,graph_missing=missing,checks=len(report.get('checks',[])))
    result['pass']=code==0 and not timed_out and report.get('pass') is True and not drift and 'SCRIPT ERROR:' not in text and '\nERROR:' not in text
    (out/'run-manifest.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
    print(json.dumps({k:result[k] for k in ('pass','scene','case','checks','elapsed_s','exit_code','timed_out','source_drift')}),flush=True)
    raise SystemExit(0 if result['pass'] else 1)


if __name__=='__main__':main()
