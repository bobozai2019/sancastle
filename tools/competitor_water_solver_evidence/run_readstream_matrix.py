"""Serial six-kernel original-alias capture / native and Godot stream replay matrix."""
import argparse
import datetime
import json
import shutil
import subprocess
import sys
from pathlib import Path
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--build',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--events',default='1484,1490,1495,1500,1537,1543');args=ap.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);base=out.parent;here=Path(__file__).parent;root=here.parents[2]
    events=[int(x) for x in args.events.split(',')]
    if len(set(events))!=len(events) or any(e not in [1484,1490,1495,1500,1537,1543] for e in events):raise ValueError('EVENT_SELECTOR')
    for name in ['logs','sources']:(out/name).mkdir()
    scripts=['run_readstream_matrix.py','make_readstream_dxbc.py','make_readstream_glsl.py','run_readstream_reference.py','run_readstream_godot.py','evidence_contract.py']
    for name in scripts:shutil.copyfile(here/name,out/'sources'/name)
    request=dict(events=events,build=identity(args.build/'manifest.json'),scope='One existing controlled identity per kernel, three captures and native replay each, Godot three times per actual stream. Not full fixture coverage or own Godot alias capture.',
        criterion='Complete normal uint4 and complete ordered metadata/value records, exact with zero additional floating-point/quantization allowance.')
    (out/'request.json').write_text(json.dumps(request,indent=2),encoding='utf-8')
    report=dict(operation_status='running',verification_status='not_evaluated',request=identity(out/'request.json'),kernels=[],errors=[])
    def save():(out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    save()
    for event in events:
        dirs={stage:base/(out.name+'_e'+str(event)+'_'+stage) for stage in ['dxbc','glsl','native','godot']}
        commands=[('dxbc',[sys.executable,str(here/'make_readstream_dxbc.py'),'--event',str(event),'--exact',str(base/'t06_exact_programs_20261025_v1'),'--hash-helper',str(base/'t06_container_hash_helper_20261025_v1'),'--output',str(dirs['dxbc'])]),
            ('glsl',[sys.executable,str(here/'make_readstream_glsl.py'),'--exact',str(base/'t06_exact_programs_20261025_v1'),'--adaptation',str(dirs['dxbc']),'--project',str(root/'tests/investigation/water_solver_evidence_probe'),'--output',str(dirs['glsl'])]),
            ('native',[sys.executable,str(here/'run_readstream_reference.py'),'--build',str(args.build),'--adaptation',str(dirs['dxbc']),'--output',str(dirs['native'])]),
            ('godot',[sys.executable,str(here/'run_readstream_godot.py'),'--reference',str(dirs['native']/'manifest.json'),'--lowering',str(dirs['glsl']),'--output',str(dirs['godot'])])]
        kernel=dict(event=event,stages=[],status='running');report['kernels'].append(kernel)
        for stage,command in commands:
            started=datetime.datetime.now(datetime.timezone.utc).isoformat();p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
            stdout,stderr=p.communicate()
            (out/'logs'/f'e{event}_{stage}.stdout.bin').write_bytes(stdout);(out/'logs'/f'e{event}_{stage}.stderr.bin').write_bytes(stderr)
            kernel['stages'].append(dict(stage=stage,command=command,pid=p.pid,exit_code=p.returncode,started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),output=str(dirs[stage])))
            save();print(json.dumps(dict(event=event,stage=stage,exit_code=p.returncode)),flush=True)
            if p.returncode:
                kernel['status']='failed';report['errors'].append(dict(event=event,stage=stage));break
        if kernel['status']=='failed':break
        native=json.loads((dirs['native']/'manifest.json').read_text());godot=json.loads((dirs['godot']/'manifest.json').read_text())
        kernel.update(status='passed',native=identity(dirs['native']/'manifest.json'),godot=identity(dirs['godot']/'manifest.json'),read_count=json.loads((dirs['dxbc']/'adaptation.json').read_text())['read_count'],capture_count=len(native['capture']['checks']),native_replay_count=len(native['replays']),godot_comparisons=len(godot['comparisons']))
        save()
    report['operation_status']='complete' if len(report['kernels'])==len(events) and not report['errors'] else 'failed';report['verification_status']='passed' if report['operation_status']=='complete' else 'failed'
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json'];save()
    print(json.dumps(dict(status=report['verification_status'],kernels=len(report['kernels']),errors=report['errors'])),flush=True);raise SystemExit(bool(report['errors']))


if __name__=='__main__':main()
