"""Record a frozen water kernel's original-alias loads and replay each actual stream."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from evidence_contract import identity


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['build','adaptation','output']:ap.add_argument('--'+key,required=True,type=Path)
    ap.add_argument('--reference-id',help='Optional exact identity from the full frozen snapshot fixture index')
    ap.add_argument('--guard-reference',type=Path,help='Reuse guards only for the identical native build and adapted programs')
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);base=out.parent
    for name in ['sources','raw','logs']:(out/name).mkdir()
    adaptation=json.loads((args.adaptation/'adaptation.json').read_text());build=json.loads((args.build/'manifest.json').read_text())
    if adaptation['verification_status']!='passed' or build['exit_code']!=0:raise ValueError('PREREQUISITE_NOT_READY')
    def checked(a):
        now=identity(a['path'])
        if now['sha256']!=a['sha256'] or now['size_bytes']!=a['size_bytes']:raise ValueError('DEPENDENCY_CHANGED:'+a['path'])
        return a
    exe_source=next(a for a in build['artifacts'] if Path(a['path']).name=='water_readstream_reference.exe');checked(exe_source)
    exe=out/'sources/water_readstream_reference.exe';shutil.copyfile(exe_source['path'],exe)
    for name in ['water_readstream_reference.cpp']:shutil.copyfile(args.build/name,out/'sources'/name)
    for name in ['run_readstream_reference.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/'sources'/name)
    event=adaptation['event'];read_count=len(adaptation['reads']);stream_bytes=adaptation['stream_bytes']
    refs=json.loads((base/'t06_snapshot_rules_full_20261025_v1/rules.json').read_text())['references'];ref=next(r for r in refs if r['event_id']==event and (not args.reference_id or r['reference_id']==args.reference_id))
    if adaptation['parent']['sha256']!=ref['original_program']['sha256']:raise ValueError('ORIGINAL_PROGRAM_PARENT_MISMATCH')
    checked(adaptation['parent']);checked(adaptation['parent_asm'])
    for a in [ref['output_seed'],ref['constants'],*ref['srvs']]:checked(a)
    capture=next(p for p in adaptation['programs'] if p['mode']=='capture');replay=next(p for p in adaptation['programs'] if p['mode']=='replay')
    for p in [capture,replay]:checked(p['program'])
    request=dict(event=event,reference_id=ref['reference_id'],read_count=read_count,stream_bytes=stream_bytes,adaptation=identity(args.adaptation/'adaptation.json'),build=identity(args.build/'manifest.json'),input=ref['output_seed'],constants=ref['constants'],srvs=ref['srvs'],programs=[capture['program'],replay['program']],repeat_count=3,
        criterion='Exact full normal-output bytes and entire declared stream metadata/value bytes per actual capture; extra floating-point/quantization allowance zero.',
        scope='Instrumented original u0 alias and fixed-stream replay only; scheduling perturbed and original unmodified equivalence not assumed.')
    (out/'request.json').write_text(json.dumps(request,indent=2),encoding='utf-8')
    report=dict(operation_status='running',verification_status='not_evaluated',request=identity(out/'request.json'),capture=None,replays=[],negatives=[],errors=[])
    def save():
        (out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    save()
    def execute(name,program,stream=None,repeat=1):
        target=out/'raw'/name
        kind='floor' if event==1484 else 'sources' if event==1537 else 'simple'
        command=[str(exe),'--program',str(program),'--input',ref['output_seed']['path'],'--constants',ref['constants']['path'],'--kind',kind,'--before-copy','1','--repeat',str(repeat),'--output',str(target)]
        if kind=='floor':command+=['--srv0',ref['srvs'][0]['path']]
        if kind=='sources':command+=['--texture0',ref['srvs'][0]['path'],'--srv1',ref['srvs'][1]['path']]
        if stream is not None:command+=['--stream-input',str(stream)]
        started=datetime.datetime.now(datetime.timezone.utc).isoformat();process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
        try:stdout,stderr=process.communicate(timeout=90)
        except subprocess.TimeoutExpired:process.kill();stdout,stderr=process.communicate();raise RuntimeError('OWNED_READSTREAM_TIMEOUT')
        (out/'logs'/(name+'.stdout.bin')).write_bytes(stdout);(out/'logs'/(name+'.stderr.bin')).write_bytes(stderr)
        return dict(command=command,pid=process.pid,exit_code=process.returncode,started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),stderr=stderr.decode(errors='replace'),output=target.as_posix())
    def proof(run,count,stream=None):
        if run['exit_code']:raise ValueError('GPU_EXECUTION_FAILED:'+run['stderr'])
        target=Path(run['output']);logs=[json.loads(x) for x in (target/'execution.jsonl').read_text().splitlines()];rows=[]
        if len(logs)!=count:raise ValueError('GPU_REPEAT_COVERAGE')
        for i,e in enumerate(logs):
            before=identity(target/f'before_{i}.bin');after=identity(target/f'after_{i}.bin');record=identity(target/f'stream_{i}.bin')
            if before['sha256']!=ref['output_seed']['sha256'] or after['size_bytes']!=2097152 or record['size_bytes']!=stream_bytes or e['fence_completed']<e['fence_ticket']:raise ValueError('GPU_INPUT_OR_COMPLETION_PROOF')
            srvs=[]
            for slot,a in enumerate(ref['srvs']):
                actual=identity(target/f'srv{slot}_before_{i}.bin')
                if actual['sha256']!=a['sha256']:raise ValueError('ORIGINAL_SRV_GPU_INPUT_CHANGED')
                srvs.append(actual)
            if stream is not None:
                t2=identity(target/f'srv2_before_{i}.bin')
                if t2['sha256']!=identity(stream)['sha256']:raise ValueError('GPU_REPLAY_INPUT_CHANGED')
            value=np.fromfile(record['path'],dtype='<u4').reshape(131072,read_count,2,4);meta=value[:,:,0,:]
            if np.any(meta[:,:,0]>=131072) or not np.all(meta[:,:,1]==np.array([r['offset'] for r in adaptation['reads']],dtype='<u4')) or not np.all(meta[:,:,2]==np.array([r['mask_bits'] for r in adaptation['reads']],dtype='<u4')) or not np.all(meta[:,:,3]==np.array([r['instruction'] for r in adaptation['reads']],dtype='<u4')):raise ValueError('STREAM_METADATA_FORMAT')
            if event==1490 and not np.array_equal(meta[:,4,0],np.arange(131072,dtype='<u4')):raise ValueError('CENTER_READ_SELECTOR')
            for slot,r in enumerate(adaptation['reads']):
                for lane,c in enumerate('xyzw'):
                    if c not in r['mask'] and np.any(value[:,slot,1,lane]):raise ValueError('UNDEFINED_LANE_NOT_ZERO')
            rows.append(dict(repeat=i,before=before,after=after,stream=record,original_srvs_before=srvs,gpu_fence_complete=True,metadata_valid=True))
        return rows
    try:
        run=execute('capture',capture['program']['path'],repeat=3);rows=proof(run,3);report['capture']=dict(run=run,checks=rows)
        save();print(json.dumps(dict(capture_repeats=len(rows),distinct_outputs=len({r['after']['sha256'] for r in rows}))),flush=True)
        for row in rows:
            run=execute('replay_'+str(row['repeat']),replay['program']['path'],row['stream']['path']);actual=proof(run,1,row['stream']['path'])[0]
            normal=actual['after']['sha256']==row['after']['sha256'];same_stream=actual['stream']['sha256']==row['stream']['sha256']
            report['replays'].append(dict(capture_repeat=row['repeat'],run=run,check=actual,normal_output_exact=normal,stream_exact=same_stream))
            if not normal or not same_stream:report['errors'].append(dict(code='CAPTURE_REPLAY_MISMATCH',repeat=row['repeat'],normal=normal,stream=same_stream))
            save();print(json.dumps(dict(replay=row['repeat'],normal_exact=normal,stream_exact=same_stream)),flush=True)
        if args.guard_reference:
            prior=json.loads(args.guard_reference.read_text());prior_request=json.loads(Path(prior['request']['path']).read_text())
            if prior['verification_status']!='passed' or prior['errors'] or prior_request['build']['sha256']!=request['build']['sha256'] or prior_request['adaptation']['sha256']!=request['adaptation']['sha256'] or len(prior['negatives'])!=5 or not all(n['passed'] for n in prior['negatives']):raise ValueError('NATIVE_GUARD_REUSE_NOT_VALID')
            report['negatives']=[dict(case=n['case'],passed=True,reused_from=identity(args.guard_reference)) for n in prior['negatives']]
        else:
            short=out/'sources/truncated_stream.bin';short.write_bytes(bytes(128))
            cases=[('original_without_u1',ref['original_program']['path'],None,'unsupported_uav_sampler_or_counter'),('capture_with_stream',capture['program']['path'],rows[0]['stream']['path'],'resource_declaration_count'),('replay_missing_stream',replay['program']['path'],None,'resource_declaration_count'),('short_stream',replay['program']['path'],short,'DEPENDENCY_SIZE_MISMATCH:stream_t2')]
            for name,program,stream,expected in cases:
                run=execute(name,program,stream);passed=run['exit_code']!=0 and expected in run['stderr'];report['negatives'].append(dict(case=name,run=run,expected=expected,passed=passed))
                if not passed:report['errors'].append('NEGATIVE_NOT_REJECTED:'+name)
            corrupt=out/'sources/corrupt_metadata_stream.bin';data=bytearray(Path(rows[0]['stream']['path']).read_bytes());data[8]^=1;corrupt.write_bytes(data)
            run=execute('corrupt_metadata',replay['program']['path'],corrupt);actual=proof(run,1,corrupt)[0]
            rejected=actual['stream']['sha256']!=identity(corrupt)['sha256'];same_output=actual['after']['sha256']==rows[0]['after']['sha256']
            report['negatives'].append(dict(case='metadata_corruption_detected_with_same_normal_output',run=run,check=actual,normal_output_same=same_output,validator_rejected=rejected,passed=rejected and same_output))
            if not rejected or not same_output:report['errors'].append('METADATA_CORRUPTION_CONTROL_NOT_DISTINGUISHED')
        report['operation_status']='complete';report['verification_status']='passed' if not report['errors'] else 'failed'
    except Exception as error:
        report['operation_status']='failed';report['errors'].append(str(error))
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json'];save()
    print(json.dumps(dict(operation=report['operation_status'],status=report['verification_status'],errors=report['errors'])),flush=True)
    raise SystemExit(bool(report['errors']))


if __name__=='__main__':main()
