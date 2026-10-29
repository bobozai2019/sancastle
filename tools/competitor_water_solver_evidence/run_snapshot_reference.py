"""Collect explicitly adapted readonly-water arithmetic references and test the real guards."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity
from reference_budget import load_budget


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--build',required=True,type=Path);ap.add_argument('--adaptation',required=True,type=Path)
    ap.add_argument('--output',required=True,type=Path);ap.add_argument('--all',action='store_true')
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    base=out.parent;budget=load_budget(base/'t03_error_budget_20261025_v1/error_budget.json')
    selected=budget['references'] if args.all else budget['references'][:6]
    adapted=json.loads((args.adaptation/'adaptation.json').read_text())
    build=json.loads((args.build/'manifest.json').read_text())
    if adapted['verification_status']!='passed' or build['exit_code']!=0:raise ValueError('ADAPTATION_OR_BUILD_NOT_READY')
    for name in ['sources','raw','logs']:(out/name).mkdir()
    source_exe=args.build/'water_snapshot_reference.exe';expected=next(a for a in build['artifacts'] if a['path']==source_exe.as_posix())
    if identity(source_exe)['sha256']!=expected['sha256']:raise ValueError('EXECUTOR_CHANGED')
    exe=out/'sources/water_snapshot_reference.exe';shutil.copyfile(source_exe,exe)
    shutil.copyfile(args.build/'water_snapshot_reference.cpp',out/'sources/water_snapshot_reference.cpp')
    for name in ['run_snapshot_reference.py','reference_budget.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/'sources'/name)
    report=dict(operation_status='running',verification_status='not_evaluated',execution_mode='explicit_readonly_snapshot_adaptation',
        scope='Adapted arithmetic reference only. Original UAV reads redirected to frozen t2; never original in-place execution or G02/G5 acceptance.',
        adaptation=identity(args.adaptation/'adaptation.json'),build=identity(args.build/'manifest.json'),references=[],controls=[],negatives=[],errors=[])
    def save():
        (out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    save()
    def execute(name,command):
        started=datetime.datetime.now(datetime.timezone.utc).isoformat()
        process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
        try:stdout,stderr=process.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            process.kill();stdout,stderr=process.communicate();raise RuntimeError('OWNED_PROCESS_TIMEOUT:'+name)
        (out/'logs'/(name+'.stdout.bin')).write_bytes(stdout);(out/'logs'/(name+'.stderr.bin')).write_bytes(stderr)
        return dict(command=command,pid=process.pid,exit_code=process.returncode,started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),stdout=stdout.decode(errors='replace'),stderr=stderr.decode(errors='replace'))
    def checked(artifact):
        actual=identity(artifact['path'])
        if actual['sha256']!=artifact['sha256'] or actual['size_bytes']!=artifact['size_bytes']:raise ValueError('DEPENDENCY_CHANGED')
        return actual
    try:
        for index,g in enumerate(selected):
            p=next(p for p in adapted['programs'] if p['event']==g['event_id'])
            if p['original']['sha256']!=g['original_program']['sha256']:raise ValueError('PROGRAM_PARENT_MISMATCH')
            for artifact in [p['adapted'],g['input'],g['constants'],*g['srvs']]:checked(artifact)
            name='snapshot_'+g['reference_id'];target=out/'raw'/name
            kind='floor' if g['event_id']==1484 else 'sources' if g['event_id']==1537 else 'simple'
            command=[str(exe),'--program',p['adapted']['path'],'--input',g['input']['path'],'--snapshot',g['input']['path'],
                '--constants',g['constants']['path'],'--kind',kind,'--before-copy','1','--repeat','3','--output',str(target)]
            if kind=='floor':command+=['--srv0',g['srvs'][0]['path']]
            if kind=='sources':command+=['--texture0',g['srvs'][0]['path'],'--srv1',g['srvs'][1]['path']]
            run=execute(name,command)
            if run['exit_code']:raise RuntimeError('ADAPTED_EXECUTION_FAILED:'+name+':'+run['stderr'])
            logs=[json.loads(line) for line in (target/'execution.jsonl').read_text().splitlines()]
            checks=[]
            for repeat,e in enumerate(logs):
                before=identity(target/('before_%d.bin'%repeat));snapshot=identity(target/('srv2_before_%d.bin'%repeat));after=identity(target/('after_%d.bin'%repeat))
                if not(e['fence_completed']>=e['fence_ticket'] and before['sha256']==g['input']['sha256'] and snapshot['sha256']==g['input']['sha256']):raise ValueError('INPUT_OR_GPU_COMPLETION_NOT_PROVEN')
                srvs=[]
                for slot,a in enumerate(g['srvs']):
                    proof=identity(target/('srv%d_before_%d.bin'%(slot,repeat)))
                    if proof['sha256']!=a['sha256']:raise ValueError('GPU_ORIGINAL_SRV_MISMATCH')
                    srvs.append(proof)
                checks.append(dict(repeat=repeat,before=before,snapshot_before=snapshot,original_srvs_before=srvs,after=after,fence_complete=True))
            if len(checks)!=3:raise ValueError('REPEAT_COUNT_MISMATCH')
            hashes={c['after']['sha256'] for c in checks}
            if len(hashes)!=1:report['errors'].append('READONLY_REPEAT_NOT_STABLE:'+name)
            report['references'].append(dict(reference_id=name,original_reference_id=g['reference_id'],event_id=g['event_id'],original_program=g['original_program'],adapted_program=p['adapted'],
                snapshot=g['input'],output_seed=g['input'],constants=g['constants'],srvs=g['srvs'],checks=checks,repeat_stable=len(hashes)==1,run=run))
            save();print(json.dumps(dict(completed=index+1,total=len(selected),reference_id=name,stable=len(hashes)==1)),flush=True)
        # Counterfactual controls only on one selected dynamic kernel; no empirical tolerance fitting.
        g=next(g for g in selected if g['event_id']==1490);ref=next(r for r in report['references'] if r['original_reference_id']==g['reference_id'])
        default=ref['run']['command'];water_bytes=512*256*16
        poison=out/'sources/output_poison.bin';poison.write_bytes(bytes([0xa5])*water_bytes)
        zeros=out/'sources/zero_snapshot.bin';zeros.write_bytes(bytes(water_bytes))
        for name,flag,file,equal_expected in [('poison_output_seed','--input',poison,True),('changed_snapshot','--snapshot',zeros,False)]:
            command=list(default);command[command.index(flag)+1]=str(file);command[command.index('--repeat')+1]='1';target=out/'raw'/name;command[command.index('--output')+1]=str(target)
            run=execute(name,command)
            if run['exit_code']:raise ValueError('CONTROL_EXECUTION_FAILED:'+name)
            after=identity(target/'after_0.bin');equal=after['sha256']==ref['checks'][0]['after']['sha256'];passed=equal==equal_expected
            report['controls'].append(dict(case=name,run=run,after=after,equal_to_default=equal,expected_equal=equal_expected,passed=passed))
            if not passed:report['errors'].append('CONTROL_NOT_DISTINGUISHED:'+name)
        bad=out/'sources/truncated_snapshot.bin';bad.write_bytes(bytes(128))
        cases=[('missing_snapshot',None,'ARGUMENT_MISSING:--snapshot'),('truncated_snapshot',bad,'DEPENDENCY_SIZE_MISMATCH:snapshot_t2'),('original_program',g['original_program']['path'],'SELECTOR_MISMATCH:resource_declaration_count')]
        for name,value,expected_error in cases:
            command=list(default);command[command.index('--output')+1]=str(out/'raw'/name)
            if name=='missing_snapshot':pos=command.index('--snapshot');del command[pos:pos+2]
            elif name=='truncated_snapshot':command[command.index('--snapshot')+1]=str(value)
            else:command[command.index('--program')+1]=str(value)
            run=execute(name,command);passed=run['exit_code']!=0 and expected_error in run['stdout']+run['stderr']
            report['negatives'].append(dict(case=name,run=run,expected=expected_error,passed=passed))
            if not passed:report['errors'].append('NEGATIVE_NOT_REJECTED:'+name)
        report['operation_status']='complete';report['verification_status']='passed' if not report['errors'] else 'failed'
    except Exception as error:
        report['operation_status']='failed';report['errors'].append(str(error))
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json'];save()
    print(json.dumps(dict(operation=report['operation_status'],status=report['verification_status'],references=len(report['references']),errors=report['errors'])),flush=True)
    raise SystemExit(bool(report['errors']))


if __name__=='__main__':main()
