"""Run a staged, serial small RDC parameter scan; phase2 requires usable phase1."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
from evidence_contract import identity


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--selection',required=True,type=Path)
    p.add_argument('--phase',choices=[1,2],type=int,required=True);p.add_argument('--output',required=True,type=Path)
    args=p.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    selection=json.loads(args.selection.read_text());tools=Path(__file__).resolve().parent
    if args.phase==2:
        for spec in selection['requests']:
            if spec['phase']!=1:continue
            req=json.loads(Path(spec['request']['path']).read_text());manifest=json.loads((Path(req['output_root'])/'manifest.json').read_text())
            stages={e['logical_stage'] for e in manifest['events']}
            if manifest['operation_status']!='complete' or manifest['errors'] or stages!={'floor','velocity','water','advection','sources','normal'}:
                raise ValueError('PHASE1_NOT_YET_USABLE')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['logs','sources','derived','raw']:(out/name).mkdir()
    results=[]
    for spec in selection['requests']:
        if spec['phase']!=args.phase:continue
        command=[sys.executable,'-X','utf8',str(tools/'run_replay.py'),'--request',spec['request']['path'],'--script',str(tools/'multicapture_replay.py')]
        print(json.dumps(dict(phase='capture',capture=spec['capture'])),flush=True)
        result=subprocess.run(command,capture_output=True,text=True)
        log=out/'logs'/(Path(spec['capture']).stem+'.txt');log.write_text(result.stdout+result.stderr,encoding='utf-8')
        results.append(dict(capture=spec['capture'],request=spec['request'],command=command,exit_code=result.returncode,log=identity(log)))
        (out/'logs/progress.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        if result.returncode:break
    for name in ['run_capture_batch.py','run_replay.py','multicapture_replay.py','evidence_contract.py']:
        (out/'sources'/name).write_bytes((tools/name).read_bytes())
    errors=[] if len(results)==len([s for s in selection['requests'] if s['phase']==args.phase]) and all(r['exit_code']==0 for r in results) else ['CAPTURE_BATCH_PARTIAL']
    (out/'manifest.json').write_text(json.dumps(dict(schema_version='1.0',run_id=out.name,operation_status='complete' if not errors else 'partial',
        verification_status='not_evaluated',errors=errors,selection=identity(args.selection),phase=args.phase,results=results,
        artifacts=[identity(p) for p in out.rglob('*') if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(results=results,errors=errors)),flush=True)
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
