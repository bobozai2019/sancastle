"""Serial reverse pairing: Godot alias records consumed by original native arithmetic."""
import argparse
import datetime
import json
import shutil
import subprocess
import sys
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source-matrix','build','output']:ap.add_argument('--'+name,type=Path,required=True)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);base=out.parent;here=Path(__file__).parent;root=here.parents[2]
    source=json.loads((args.source_matrix/'manifest.json').read_text())
    if source['verification_status']!='passed' or source['errors']:raise ValueError('SOURCE_MATRIX_NOT_READY')
    for name in ['sources','logs']:(out/name).mkdir()
    for name in ['run_godot_readstream_matrix.py','run_godot_readstream_record.py','make_readstream_glsl.py','evidence_contract.py']:shutil.copyfile(here/name,out/'sources'/name)
    request=dict(source_matrix=identity(args.source_matrix/'manifest.json'),build=identity(args.build/'manifest.json'),events=[k['event'] for k in source['kernels']],
        scope='Six existing per-kernel controlled identities; actual Godot single-water-SSBO alias record three times, exact original-arithmetic replay per stream. No full fixture or sequence/lifecycle claim.')
    (out/'request.json').write_text(json.dumps(request,indent=2),encoding='utf-8')
    report=dict(operation_status='running',verification_status='not_evaluated',request=identity(out/'request.json'),kernels=[],errors=[]);guard_reference=None
    def save():(out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    save()
    for kernel in source['kernels']:
        event=kernel['event'];adaptation=Path(next(s['output'] for s in kernel['stages'] if s['stage']=='dxbc'));fixture=Path(kernel['native']['path']);glsl=base/(out.name+f'_e{event}_glsl');record=base/(out.name+f'_e{event}_record')
        commands=[('glsl',[sys.executable,str(here/'make_readstream_glsl.py'),'--mode','in_place_record','--exact',str(base/'t06_exact_programs_20261025_v1'),'--adaptation',str(adaptation),'--project',str(root/'tests/investigation/water_solver_evidence_probe'),'--output',str(glsl)]),
            ('record',[sys.executable,str(here/'run_godot_readstream_record.py'),'--native-reference',str(fixture),'--lowering',str(glsl),'--build',str(args.build),'--output',str(record)])]
        if guard_reference:commands[1][1].extend(['--guard-reference',str(guard_reference)])
        item=dict(event=event,stages=[],status='running');report['kernels'].append(item)
        for stage,command in commands:
            start=datetime.datetime.now(datetime.timezone.utc).isoformat();p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW);stdout,stderr=p.communicate()
            (out/'logs'/f'e{event}_{stage}.stdout.bin').write_bytes(stdout);(out/'logs'/f'e{event}_{stage}.stderr.bin').write_bytes(stderr)
            item['stages'].append(dict(stage=stage,command=command,pid=p.pid,exit_code=p.returncode,started_at=start,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),output=str(glsl if stage=='glsl' else record)))
            save();print(json.dumps(dict(event=event,stage=stage,exit_code=p.returncode)),flush=True)
            if p.returncode:item['status']='failed';report['errors'].append(dict(event=event,stage=stage));break
        if item['status']=='failed':break
        result=json.loads((record/'manifest.json').read_text());item.update(status='passed',record=identity(record/'manifest.json'),paired_records=len(result['records']),read_count=result['read_count'])
        if guard_reference is None:guard_reference=record/'manifest.json'
        save()
    report['operation_status']='complete' if not report['errors'] and len(report['kernels'])==len(source['kernels']) else 'failed';report['verification_status']='passed' if report['operation_status']=='complete' else 'failed'
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json'];save()
    print(json.dumps(dict(status=report['verification_status'],kernels=len(report['kernels']),errors=report['errors'])),flush=True);raise SystemExit(bool(report['errors']))


if __name__=='__main__':main()
