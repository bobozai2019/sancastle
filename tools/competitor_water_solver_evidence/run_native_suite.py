"""Execute six original water kernels with complete dependencies and copy control."""
import argparse
import datetime
import itertools
import json
import shutil
import subprocess
from pathlib import Path
from evidence_contract import identity
from analyze_repeats import difference

STAGES={1484:('floor',1484,'f6f8c17d743aa60c2fa01cf4cd0a9a03ab1bddad297da2a8f729aef6356d6bc3'),
        1490:('simple',1484,'9e5c7da8738200d374076a6cc3b48be52fdbad70e8c8dc2bd27eb75431d30523'),
        1495:('simple',1490,'549114c23f1921610bacaf1d9ae375814fda1fb1de492cc2a4acfc53a502c64f'),
        1500:('simple',1495,'b2794ecb18de815ff607fffd734ff4cde859bab1efd7fa3dfe9a24eb5a9f7a3c'),
        1537:('sources',1530,'a61d34e411e8eee5c795bf233908a9b2a5b85ee272f5d0fbcb1481da27a62b80'),
        1543:('simple',1537,'38a7f089261c54713b583b0f9a6bdd876d09cdb7859e64a804c06e08d64fa2a6')}


def write(path,data):path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')


def checked_copy(artifact,target):
    actual=identity(artifact['path'])
    if actual['sha256']!=artifact['sha256'] or actual['size_bytes']!=artifact['size_bytes']:
        raise ValueError('SOURCE_CHANGED:'+artifact['path'])
    shutil.copyfile(artifact['path'],target)
    return dict(identity(target),source=artifact)


def run(command,log_prefix):
    start=datetime.datetime.now(datetime.timezone.utc).isoformat()
    result=subprocess.run(command,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
    log_prefix.with_suffix('.stdout.bin').write_bytes(result.stdout)
    log_prefix.with_suffix('.stderr.bin').write_bytes(result.stderr)
    return dict(command=command,started_at=start,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                exit_code=result.returncode,stdout=result.stdout.decode('utf-8',errors='replace'),stderr=result.stderr.decode('utf-8',errors='replace'))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay-manifest',type=Path,required=True)
    parser.add_argument('--build',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['raw','sources','derived','logs']:(out/name).mkdir()
    report=dict(schema_version='1.0',run_id=out.name,operation_status='failed',verification_status='not_evaluated',
                errors=[],references=[],negative_checks=[],artifacts=[],numeric_budget=None,
                scope='Six-kernel controlled raw reference and copy perturbation; not original temporal trajectory or Godot equivalence')
    write(out/'manifest.json',report)
    try:
        m=json.loads(args.replay_manifest.read_text())
        if m['source']['sha256']!='761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2':raise ValueError('SOURCE_IDENTITY_MISMATCH')
        rows={e['event_id']:e for e in m['events']}
        build=json.loads((args.build/'manifest.json').read_text())
        if build['exit_code']!=0:raise ValueError('BUILD_FAILED')
        for artifact in build['artifacts']:
            if Path(artifact['path']).name in ['water_reference.exe','water_reference.cpp','build.cmd','build_stdout.bin','build_stderr.bin']:
                checked_copy(artifact,out/'sources'/Path(artifact['path']).name)
        if identity(out/'sources/water_reference.cpp')['sha256']!=identity(Path(__file__).with_name('native_reference')/'water_reference.cpp')['sha256']:
            raise ValueError('SOURCE_CHANGED:executable_cpp')
        shutil.copyfile(args.build/'manifest.json',out/'sources/build_manifest.json')
        for name in ['run_native_suite.py','evidence_contract.py','analyze_repeats.py']:
            shutil.copyfile(Path(__file__).with_name(name),out/'sources'/name)
        exe=out/'sources/water_reference.exe'
        requests=[]
        for eid,(kind,feed,program_hash) in STAGES.items():
            row=rows[eid]
            if row['program']['sha256']!=program_hash:raise ValueError('SELECTOR_MISMATCH:program')
            directory=out/'sources'/('e%d'%eid);directory.mkdir()
            program=checked_copy(row['program'],directory/'program.dxbc')
            cb=checked_copy(row['constants'][0]['raw'],directory/'constants.bin')
            seed=checked_copy(next(b['raw'] for b in rows[feed]['bindings'] if b['access']=='uav'),directory/'water.bin')
            srvs=[]
            for binding in row['bindings']:
                if binding['access']=='srv':
                    item=checked_copy(binding['raw'],directory/('srv%d.bin'%binding['index']))
                    item['selector']={k:v for k,v in binding.items() if k!='raw'}
                    srvs.append(item)
            for copy in [1,0]:
                target=out/'raw'/('e%d_copy%d'%(eid,copy))
                command=[str(exe),'--program',program['path'],'--input',seed['path'],'--constants',cb['path'],
                         '--output',str(target),'--kind',kind,'--before-copy',str(copy),'--repeat','3']
                for srv in srvs:
                    option='--texture0' if 'texture' in srv['selector'] else '--srv%d'%srv['selector']['index']
                    command.extend([option,srv['path']])
                requests.append(dict(reference_id='e%d_copy%d'%(eid,copy),event_id=eid,kind=kind,before_copy=bool(copy),
                    program=program,constants=cb,input=seed,srvs=srvs,output=str(target),command=command,
                    feed_event_id=feed,input_origin='Controlled fixture selected from post-event replay; not original same-dispatch pre-state',
                    original_binding=row['bindings'],original_root_signature='See T01 stage_map and D3D12 pipeline dump',
                    pairing_kind='reconstructed_controlled',hidden_counters='none in executable declarations; counter layouts/instructions rejected, RDEF cross-checked only when present',
                    numeric_budget=None))
        write(out/'request.json',dict(frozen_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            source_manifest=identity(args.replay_manifest),executable=identity(exe),requests=requests,
            variation='Only before-dispatch readback copies and the transitions they require; no shader, input or dispatch change between matched copy modes',
            hypotheses=['A bounded copy perturbation may or may not dominate original in-place schedule variation',
                        'Other kernels may have different repeatability from E1495'],
            limitation='Buffer SRVs use immutable UPLOAD resources; source texture uses DEFAULT, restored each dispatch. Original heap placement is not claimed. No performance measurement.'))
        for req in requests:
            print(json.dumps(dict(phase='reference',reference_id=req['reference_id'])),flush=True)
            result=run(req['command'],out/'logs'/req['reference_id'])
            result.update(reference_id=req['reference_id'],request=req,pairing_kind='unproven')
            if result['exit_code']:
                report['errors'].append(dict(code='NATIVE_EXECUTION_FAILED',reference_id=req['reference_id'],stderr=result['stderr']))
                report['references'].append(result);raise ValueError('NATIVE_EXECUTION_FAILED')
            target=Path(req['output']);logs=[json.loads(line) for line in (target/'execution.jsonl').read_text().splitlines()]
            checks=[]
            if len(logs)!=3:raise ValueError('REFERENCE_INCOMPLETE')
            for repeat,log in enumerate(logs):
                if log['fence_completed']<log['fence_ticket']:raise ValueError('GPU_NOT_COMPLETE')
                output=identity(target/('after_%d.bin'%repeat))
                if output['size_bytes']!=2097152:raise ValueError('DEPENDENCY_SIZE_MISMATCH:output')
                checked=dict(repeat=repeat,output=output,fence_complete=True,water_restored_by_copy_command=True,srv_snapshots=[])
                if req['before_copy']:
                    before=identity(target/('before_%d.bin'%repeat));checked['before']=before
                    if before['sha256']!=req['input']['sha256']:raise ValueError('INPUT_NOT_RESTORED:water')
                    for srv in req['srvs']:
                        snapshot=identity(target/('srv%d_before_%d.bin'%(srv['selector']['index'],repeat)))
                        if snapshot['sha256']!=srv['sha256']:raise ValueError('INPUT_NOT_RESTORED:srv')
                        checked['srv_snapshots'].append(snapshot)
                checks.append(checked)
            result.update(pairing_kind='reconstructed_controlled',checks=checks,
                          device=identity(target/'device.json'),execution=identity(target/'execution.jsonl'))
            report['references'].append(result)
            write(out/'manifest_partial.json',report)
        # Actual negative executions use original programs with a deliberately
        # wrong layout or missing/truncated input; no synthetic shader is needed.
        byid={r['reference_id']:r['request'] for r in report['references']}
        floor=byid['e1484_copy1'];water=byid['e1495_copy1'];sources=byid['e1537_copy1']
        truncated=out/'sources/truncated.bin';truncated.write_bytes(b'negative fixture')
        cases=[('wrong_kind',water,'SELECTOR_MISMATCH',{'--kind':'sources'}),
               ('missing_sources',sources,'DEPENDENCY_MISSING',{'--texture0':None,'--srv1':None}),
               ('truncated_sand',floor,'DEPENDENCY_SIZE_MISMATCH',{'--srv0':str(truncated)}),
               ('wrong_constant_extent',water,'DEPENDENCY_SIZE_MISMATCH',{'--constants':str(truncated)}),
               ('unhandled_counter_option',water,'UNSUPPORTED_ARGUMENT',{'--counter-initialized':'0'})]
        for name,req,expected,changes in cases:
            options=dict(zip(req['command'][1::2],req['command'][2::2]));options['--output']=str(out/'raw'/('reject_'+name))
            for k,v in changes.items():
                if v is None:options.pop(k,None)
                else:options[k]=v
            command=[str(exe)]+[item for pair in options.items() for item in pair]
            result=run(command,out/'logs'/('negative_'+name));result.update(name=name,expected=expected,
                passed=result['exit_code']!=0 and expected in result['stderr'] and not Path(options['--output']).exists())
            report['negative_checks'].append(result)
            if not result['passed']:report['errors'].append(dict(code='NEGATIVE_CHECK_FAILED',name=name))
        write(out/'derived/negative_checks.json',report['negative_checks'])
        comparisons=[]
        for eid in STAGES:
            for copy in [1,0]:
                target=out/'raw'/('e%d_copy%d'%(eid,copy))
                for left,right in itertools.combinations(range(3),2):
                    comparisons.append(dict(event_id=eid,comparison='within_mode',before_copy=bool(copy),left=left,right=right,
                        metric=difference(target/('after_%d.bin'%left),target/('after_%d.bin'%right))))
            leftroot=out/'raw'/('e%d_copy1'%eid);rightroot=out/'raw'/('e%d_copy0'%eid)
            for left,right in itertools.product(range(3),repeat=2):
                comparisons.append(dict(event_id=eid,comparison='copy_perturbation',left=left,right=right,
                    metric=difference(leftroot/('after_%d.bin'%left),rightroot/('after_%d.bin'%right))))
        write(out/'derived/repeat_and_copy_metrics.json',comparisons)
        report['operation_status']='complete';report['verification_status']='failed' if report['errors'] else 'passed'
    except Exception as error:
        report['errors'].append(dict(code='SUITE_EXCEPTION',message=str(error)));report['verification_status']='failed'
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json']
    write(out/'manifest.json',report)
    print(json.dumps(dict(operation_status=report['operation_status'],verification_status=report['verification_status'],errors=report['errors'])),flush=True)
    raise SystemExit(1 if report['errors'] else 0)


if __name__=='__main__':main()
