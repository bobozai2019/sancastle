"""Compare Godot against individually paired original-alias native read streams."""
import argparse
import datetime
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from evidence_contract import identity
from reference_budget import codes,metrics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['reference','lowering','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--guard-reference',type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','comparisons','negative']:(out/name).mkdir()
    root=Path(__file__).resolve().parents[3];project=root/'tests/investigation/water_solver_evidence_probe'
    reference=json.loads(args.reference.read_text());lowering=json.loads((args.lowering/'lowering.json').read_text())
    if reference['operation_status']!='complete' or reference['verification_status']!='passed' or reference['errors']:raise ValueError('NATIVE_READSTREAM_REFERENCE_NOT_READY')
    def checked(a):
        actual=identity(a['path'])
        if actual['sha256']!=a['sha256'] or actual['size_bytes']!=a['size_bytes']:raise ValueError('SOURCE_CHANGED:'+a['path'])
        return a
    for key in ['shader','probe','scene','source']:checked(lowering[key])
    parent=json.loads(Path(reference['request']['path']).read_text());checked(reference['request'])
    checked(parent['adaptation'])
    adaptation=json.loads(Path(parent['adaptation']['path']).read_text())
    event=adaptation['event'];read_count=len(adaptation['reads']);stream_bytes=adaptation['stream_bytes']
    if lowering['adaptation']['sha256']!=parent['adaptation']['sha256'] or lowering['source']['sha256']!=adaptation['parent_asm']['sha256']:raise ValueError('REFERENCE_LOWERING_PARENT_MISMATCH')
    for a in [parent['input'],parent['constants'],*parent.get('srvs',[])]:checked(a)
    cases=[]
    for row in reference['capture']['checks']:
        for key in ['before','after','stream']:checked(row[key])
        cases.append(dict(case_id='e'+str(event)+'_capture_'+str(row['repeat']),event_id=event,read_count=read_count,execution_mode='read_stream',register_trace=True,
            shader_path='res://shaders/e'+str(event)+'_read_stream.glsl',shader_sha256=lowering['shader']['sha256'],
            input=parent['input'],constants=parent['constants'],srvs=parent.get('srvs',[]),stream_input=row['stream'],native_output=row['after']))
    request=dict(schema_version='1.0',repeat_count=3,execution_mode='explicit_read_stream_replay',output_root=(out/'raw').as_posix(),cases=cases,
        reference=identity(args.reference),lowering=identity(args.lowering/'lowering.json'),
        criterion='Exact 2097152 normal bytes and declared read-count metadata/value stream bytes for each corresponding native capture. No additional float or quantization allowance.',
        scope='Paired instrumented original-alias reads, not unmodified original schedule prediction or sequence/lifecycle acceptance.')
    file=out/'request.json';file.write_text(json.dumps(request,indent=2),encoding='utf-8')
    for p in [*project.glob('*.gd'),*project.glob('*.tscn'),project/'project.godot',Path(lowering['shader']['path'])]:shutil.copyfile(p,out/'sources'/p.name)
    for name in ['run_readstream_godot.py','reference_budget.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/'sources'/name)
    godot=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe');runs=[]
    report=dict(operation_status='running',verification_status='not_evaluated',request=identity(file),comparisons=[],negatives=[],errors=[],runs=runs)
    def save():
        (out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    save()
    def execute(name,request_path,target):
        command=[str(godot),'--path',str(project),'--rendering-method','mobile','--rendering-driver','vulkan','--log-file',str(out/(name+'_engine.log')),'res://stream_probe.tscn','--','--request',str(request_path)]
        started=datetime.datetime.now(datetime.timezone.utc).isoformat();p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
        try:stdout,stderr=p.communicate(timeout=180)
        except subprocess.TimeoutExpired:p.kill();stdout,stderr=p.communicate();raise RuntimeError('OWNED_GODOT_READSTREAM_TIMEOUT')
        (out/(name+'_stdout.bin')).write_bytes(stdout);(out/(name+'_stderr.bin')).write_bytes(stderr)
        runs.append(dict(command=command,pid=p.pid,exit_code=p.returncode,started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat()))
        result=target/'probe_result.json'
        return p.returncode,json.loads(result.read_text()) if result.exists() else None
    try:
        exit_code,result=execute('main',file,out/'raw')
        if exit_code or not result or result['operation_status']!='complete' or not result['local_device_released']:raise ValueError('GODOT_STREAM_RUN_FAILED')
        if len(result['cases'])!=len(cases):raise ValueError('CASE_COVERAGE')
        for actual in result['cases']:
            case=next(c for c in cases if c['case_id']==actual['case_id']);proof=actual['gpu_dependency_hashes']
            if actual['execution_mode']!='read_stream' or proof.get('stream_input')!=case['stream_input']['sha256'] or proof.get('stream_input_after')!=case['stream_input']['sha256'] or proof.get('cb')!=case['constants']['sha256']:raise ValueError('GPU_DEPENDENCY_PROOF')
            for suffix,item in [('cb_before',case['constants']),('stream_input_before',case['stream_input']),('stream_input_after',case['stream_input'])]:
                if identity(out/'raw'/(case['case_id']+'_'+suffix+'.bin'))['sha256']!=item['sha256']:raise ValueError('SAVED_GPU_DEPENDENCY_PROOF')
            for slot,item in enumerate(case['srvs']):
                key='texture' if event==1537 and slot==0 else 'auxiliary';suffix='texture_before' if key=='texture' else 'aux_before'
                if proof.get(key)!=item['sha256'] or identity(out/'raw'/(case['case_id']+'_'+suffix+'.bin'))['sha256']!=item['sha256']:raise ValueError('ORIGINAL_SRV_GPU_INPUT_CHANGED')
            expected=np.fromfile(case['native_output']['path'],dtype='<u4');expected_stream=np.fromfile(case['stream_input']['path'],dtype='<u4').reshape(131072,read_count,2,4);expected_codes=codes(case['native_output']['path'])
            if len(actual['repeats'])!=3:raise ValueError('REPEAT_COVERAGE')
            for repeat in actual['repeats']:
                if repeat['before_sha256']!=case['input']['sha256']:raise ValueError('GPU_WATER_INPUT')
                candidate=identity(repeat['after']);stream=identity(out/'raw'/(case['case_id']+'_'+str(repeat['index'])+'_stream_output.bin'))
                if candidate['size_bytes']!=2097152 or stream['size_bytes']!=stream_bytes:raise ValueError('TRUNCATED_OUTPUT')
                words=np.fromfile(candidate['path'],dtype='<u4');stream_words=np.fromfile(stream['path'],dtype='<u4').reshape(131072,read_count,2,4);decoded=codes(candidate['path'])
                nm=int(np.count_nonzero(words!=expected));sm=int(np.count_nonzero(stream_words!=expected_stream));meta=int(np.count_nonzero(stream_words[:,:,0,:]!=expected_stream[:,:,0,:]));payload=int(np.count_nonzero(stream_words[:,:,1,:]!=expected_stream[:,:,1,:]))
                comparison=dict(case_id=case['case_id'],repeat=repeat['index'],candidate=candidate,native=case['native_output'],stream=stream,native_stream=case['stream_input'],normal_word_mismatches=nm,stream_word_mismatches=sm,
                    metadata_word_mismatches=meta,payload_word_mismatches=payload,first_normal_word=int(np.flatnonzero(words!=expected)[0]) if nm else None,
                    first_stream_component=[int(x) for x in np.argwhere(stream_words!=expected_stream)[0]] if sm else None,
                    fields={f:metrics(decoded[f],expected_codes[f]) for f in decoded},verification_status='passed' if not nm and not sm else 'failed')
                path=out/'comparisons'/(case['case_id']+'_'+str(repeat['index'])+'.json');path.write_text(json.dumps(comparison,indent=2),encoding='utf-8')
                report['comparisons'].append(dict(case_id=case['case_id'],repeat=repeat['index'],status=comparison['verification_status'],report=identity(path)))
                if nm or sm:report['errors'].append(dict(case_id=case['case_id'],repeat=repeat['index'],normal=nm,metadata=meta,payload=payload))
        report['gpu_result']=result;save()
        # Real scene guards: correct hash with short extent, wrong identity, and unsupported mode.
        if args.guard_reference:
            prior=json.loads(args.guard_reference.read_text());q=json.loads(Path(prior['request']['path']).read_text());old_lower=json.loads(Path(q['lowering']['path']).read_text())
            if prior['verification_status']!='passed' or prior['errors'] or old_lower['probe']['sha256']!=lowering['probe']['sha256'] or old_lower['shader']['sha256']!=lowering['shader']['sha256'] or len(prior['negatives'])!=4 or not all(n['passed'] for n in prior['negatives']):raise ValueError('GODOT_GUARD_REUSE_NOT_VALID')
            report['negatives']=[dict(case=n['case'],passed=True,reused_from=identity(args.guard_reference)) for n in prior['negatives']]
        else:
            short=out/'sources/truncated_stream.bin';short.write_bytes(bytes(128))
            empty=out/'sources/empty_stream.bin';empty.write_bytes(b'')
            for name,error in [('short_stream','READ_STREAM_EXTENT_MISMATCH'),('wrong_identity','ARTIFACT_IDENTITY_MISMATCH'),('empty_stream','EMPTY_ARTIFACT'),('wrong_mode','READ_STREAM_PILOT_MODE_REQUIRED')]:
                case=json.loads(json.dumps(cases[0]));target=out/'negative'/name;target.mkdir()
                if name=='short_stream':case['stream_input']=identity(short)
                elif name=='empty_stream':case['stream_input']=identity(empty)
                elif name=='wrong_identity':case['stream_input']['sha256']='0'*64
                else:case['execution_mode']='in_place'
                negative=dict(schema_version='1.0',repeat_count=1,output_root=target.as_posix(),cases=[case]);q=out/'negative'/(name+'_request.json');q.write_text(json.dumps(negative,indent=2),encoding='utf-8')
                code,actual=execute(name,q,target);passed=code!=0 and actual and actual['operation_status']=='failed' and actual['local_device_released'] and any(error in s for s in actual['errors'])
                report['negatives'].append(dict(case=name,expected=error,exit_code=code,result=actual,passed=bool(passed)))
                if not passed:report['errors'].append('NEGATIVE_NOT_REJECTED:'+name)
        report['operation_status']='complete';report['verification_status']='failed' if report['errors'] else 'passed'
    except Exception as error:
        report['operation_status']='failed';report['errors'].append(str(error))
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json'];save()
    print(json.dumps(dict(operation=report['operation_status'],status=report['verification_status'],comparisons=len(report['comparisons']),errors=report['errors'])),flush=True)
    raise SystemExit(bool(report['errors']))


if __name__=='__main__':main()
