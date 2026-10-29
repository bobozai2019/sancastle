"""Frozen 72-fixture bidirectional read-stream matrix, serialized GPU execution."""
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
    for name in ['native-matrix','record-matrix','build','output']:ap.add_argument('--'+name,type=Path,required=True)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);base=out.parent;here=Path(__file__).parent;root=here.parents[2]
    native=json.loads((args.native_matrix/'manifest.json').read_text());record=json.loads((args.record_matrix/'manifest.json').read_text())
    if native['verification_status']!='passed' or record['verification_status']!='passed' or len(native['kernels'])!=6 or len(record['kernels'])!=6:raise ValueError('SIX_KERNEL_PRECONDITION')
    rule_path=base/'t06_snapshot_rules_full_20261025_v1/rules.json';refs=json.loads(rule_path.read_text())['references']
    if len(refs)!=72 or len({r['reference_id'] for r in refs})!=72:raise ValueError('FROZEN_FIXTURE_COVERAGE')
    for name in ['sources','logs']:(out/name).mkdir()
    for name in ['run_readstream_full.py','make_readstream_glsl.py','run_readstream_reference.py','run_readstream_godot.py','run_godot_readstream_record.py','evidence_contract.py']:shutil.copyfile(here/name,out/'sources'/name)
    request=dict(fixtures=[dict(reference_id=r['reference_id'],event=r['event_id'],input=r['snapshot'],constants=r['constants'],srvs=r['srvs'],original_program=r['original_program']) for r in refs],
        fixture_index=identity(rule_path),native_templates=identity(args.native_matrix/'manifest.json'),record_templates=identity(args.record_matrix/'manifest.json'),build=identity(args.build/'manifest.json'),
        criterion='Each actual native or Godot alias stream is independently replayed. All normal packed words and all computed metadata/value records exactly equal; no extra float/quantization allowance.',
        scope='Full existing 72 single-kernel fixture identities; instrumented alias paths. Not a universal schedule proof or short-sequence/lifecycle acceptance.')
    (out/'request.json').write_text(json.dumps(request,indent=2),encoding='utf-8')
    report=dict(operation_status='running',verification_status='not_evaluated',request=identity(out/'request.json'),templates=[],fixtures=[],errors=[])
    def save():(out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    save()
    def execute(label,command):
        started=datetime.datetime.now(datetime.timezone.utc).isoformat();p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW);stdout,stderr=p.communicate()
        (out/'logs'/(label+'.stdout.bin')).write_bytes(stdout);(out/'logs'/(label+'.stderr.bin')).write_bytes(stderr)
        return dict(command=command,pid=p.pid,exit_code=p.returncode,started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    templates={}
    for n in native['kernels']:
        event=n['event'];adapter=Path(next(s['output'] for s in n['stages'] if s['stage']=='dxbc'));read_lower=base/(out.name+f'_e{event}_read_glsl')
        r=next(k for k in record['kernels'] if k['event']==event);record_lower=Path(next(s['output'] for s in r['stages'] if s['stage']=='glsl'))
        command=[sys.executable,str(here/'make_readstream_glsl.py'),'--exact',str(base/'t06_exact_programs_20261025_v1'),'--adaptation',str(adapter),'--project',str(root/'tests/investigation/water_solver_evidence_probe'),'--output',str(read_lower)]
        run=execute(f'e{event}_prepare',command)
        if run['exit_code']:report['errors'].append(dict(stage='prepare',event=event));break
        templates[event]=dict(adapter=adapter,read_lower=read_lower,record_lower=record_lower,native_guards=Path(n['native']['path']),godot_guards=None)
        report['templates'].append(dict(event=event,run=run,adapter=identity(adapter/'adaptation.json'),read_lowering=identity(read_lower/'lowering.json'),record_lowering=identity(record_lower/'lowering.json')));save()
    common_record_guard=Path(record['kernels'][0]['record']['path'])
    if not report['errors']:
        for ordinal,ref in enumerate(refs):
            event=ref['event_id'];t=templates[event];tag=out.name+f'_c{ordinal:03d}_e{event}';dirs={stage:base/(tag+'_'+stage) for stage in ['native','godot','alias']}
            item=dict(reference_id=ref['reference_id'],event=event,ordinal=ordinal,status='running',stages=[]);report['fixtures'].append(item);save()
            commands=[('native',[sys.executable,str(here/'run_readstream_reference.py'),'--build',str(args.build),'--adaptation',str(t['adapter']),'--reference-id',ref['reference_id'],'--guard-reference',str(t['native_guards']),'--output',str(dirs['native'])]),
                ('godot',[sys.executable,str(here/'run_readstream_godot.py'),'--reference',str(dirs['native']/'manifest.json'),'--lowering',str(t['read_lower']),'--output',str(dirs['godot'])]),
                ('alias',[sys.executable,str(here/'run_godot_readstream_record.py'),'--native-reference',str(dirs['native']/'manifest.json'),'--lowering',str(t['record_lower']),'--build',str(args.build),'--guard-reference',str(common_record_guard),'--output',str(dirs['alias'])])]
            if t['godot_guards']:commands[1][1].extend(['--guard-reference',str(t['godot_guards'])])
            for stage,command in commands:
                run=execute(f'c{ordinal:03d}_{stage}',command);item['stages'].append(dict(stage=stage,run=run,output=str(dirs[stage])));save()
                if run['exit_code']:item['status']='failed';report['errors'].append(dict(reference_id=ref['reference_id'],stage=stage));break
            if item['status']=='failed':break
            item.update(status='passed',native=identity(dirs['native']/'manifest.json'),godot=identity(dirs['godot']/'manifest.json'),alias=identity(dirs['alias']/'manifest.json'))
            if t['godot_guards'] is None:t['godot_guards']=dirs['godot']/'manifest.json'
            save();print(json.dumps(dict(completed=ordinal+1,total=72,event=event,reference_id=ref['reference_id'],status='passed')),flush=True)
    report['operation_status']='complete' if not report['errors'] and len(report['fixtures'])==72 else 'failed';report['verification_status']='passed' if report['operation_status']=='complete' else 'failed'
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json'];save()
    print(json.dumps(dict(status=report['verification_status'],fixtures=len(report['fixtures']),errors=report['errors'])),flush=True);raise SystemExit(bool(report['errors']))


if __name__=='__main__':main()
