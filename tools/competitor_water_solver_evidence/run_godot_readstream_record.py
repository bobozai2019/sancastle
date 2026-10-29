"""Run actual Godot water alias recording, then replay each stream with original DXBC arithmetic."""
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
    for name in ['native-reference','lowering','build','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--guard-reference',type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','native','logs','guards']:(out/name).mkdir()
    root=Path(__file__).resolve().parents[3];project=root/'tests/investigation/water_solver_evidence_probe'
    def checked(a):
        now=identity(a['path'])
        if now['sha256']!=a['sha256'] or now['size_bytes']!=a['size_bytes']:raise ValueError('SOURCE_CHANGED:'+a['path'])
        return a
    reference=json.loads(args.native_reference.read_text());lower=json.loads((args.lowering/'lowering.json').read_text());build=json.loads((args.build/'manifest.json').read_text())
    if reference['verification_status']!='passed' or reference['errors'] or lower['mode']!='instrumented_godot_in_place_record' or build['exit_code']!=0:raise ValueError('PREREQUISITE_NOT_READY')
    checked(reference['request']);fixture=json.loads(Path(reference['request']['path']).read_text());checked(fixture['adaptation']);adaptation=json.loads(Path(fixture['adaptation']['path']).read_text())
    event=adaptation['event'];read_count=len(adaptation['reads']);stream_bytes=adaptation['stream_bytes']
    if lower['event']!=event or lower['adaptation']['sha256']!=fixture['adaptation']['sha256'] or lower['source']['sha256']!=adaptation['parent_asm']['sha256']:raise ValueError('PROGRAM_PARENT_MISMATCH')
    for a in [lower['shader'],lower['probe'],lower['scene'],fixture['input'],fixture['constants'],*fixture['srvs']]:checked(a)
    replay=next(p for p in adaptation['programs'] if p['mode']=='replay');checked(replay['program'])
    exe=next(a for a in build['artifacts'] if Path(a['path']).name=='water_readstream_reference.exe');checked(exe);shutil.copyfile(exe['path'],out/'sources/water_readstream_reference.exe')
    case=dict(case_id=f'e{event}_godot_alias',event_id=event,read_count=read_count,execution_mode='in_place_record',register_trace=True,
        shader_path='res://shaders/'+Path(lower['shader']['path']).name,shader_sha256=lower['shader']['sha256'],input=fixture['input'],constants=fixture['constants'],srvs=fixture['srvs'])
    request=dict(schema_version='1.0',repeat_count=3,output_root=(out/'raw').as_posix(),cases=[case],lowering=identity(args.lowering/'lowering.json'),fixture_reference=identity(args.native_reference),native_build=identity(args.build/'manifest.json'),
        criterion='Each actual Godot alias record must be reproduced by native original-arithmetic stream replay: normal bytes and complete computed metadata/value records exactly, zero padding.',
        scope='Instrumented Godot original-alias path, not uninstrumented schedule equivalence or sequence/lifecycle acceptance.')
    file=out/'request.json';file.write_text(json.dumps(request,indent=2),encoding='utf-8')
    for p in [*project.glob('*.gd'),*project.glob('*.tscn'),project/'project.godot',Path(lower['shader']['path'])]:shutil.copyfile(p,out/'sources'/p.name)
    for name in ['run_godot_readstream_record.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/'sources'/name)
    report=dict(operation_status='running',verification_status='not_evaluated',request=identity(file),event=event,read_count=read_count,stream_bytes=stream_bytes,records=[],guards=[],guard_probe_sha256=lower['probe']['sha256'],runs=[],errors=[])
    def save():(out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    save()
    def run(name,command,timeout=120):
        started=datetime.datetime.now(datetime.timezone.utc).isoformat();p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
        try:stdout,stderr=p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:p.kill();stdout,stderr=p.communicate();raise RuntimeError('OWNED_ALIAS_RECORD_TIMEOUT')
        (out/'logs'/(name+'.stdout.bin')).write_bytes(stdout);(out/'logs'/(name+'.stderr.bin')).write_bytes(stderr)
        report['runs'].append(dict(name=name,command=command,pid=p.pid,exit_code=p.returncode,started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat()));return p.returncode
    godot='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
    def godot_command(q,name):return [godot,'--path',str(project),'--rendering-method','mobile','--rendering-driver','vulkan','--log-file',str(out/(name+'_engine.log')),'res://stream_probe.tscn','--','--request',str(q)]
    def stream_valid(path):
        a=np.fromfile(path,dtype='<u4').reshape(131072,read_count,2,4);meta=a[:,:,0,:]
        if np.any(meta[:,:,0]>=131072):raise ValueError('RECORDED_ADDRESS_OUT_OF_DOMAIN')
        for column,key in [(1,'offset'),(2,'mask_bits'),(3,'instruction')]:
            if not np.all(meta[:,:,column]==np.array([r[key] for r in adaptation['reads']],dtype='<u4')):raise ValueError('RECORDED_METADATA_MISMATCH')
        for slot,r in enumerate(adaptation['reads']):
            for lane,c in enumerate('xyzw'):
                if c not in r['mask'] and np.any(a[:,slot,1,lane]):raise ValueError('UNRECORDED_LANE_NOT_ZERO')
    try:
        code=run('godot_alias_record',godot_command(file,'record'))
        result=json.loads((out/'raw/probe_result.json').read_text())
        if code or result['operation_status']!='complete' or not result['local_device_released'] or len(result['cases'])!=1:raise ValueError('GODOT_ALIAS_RECORD_FAILED')
        actual=result['cases'][0];deps=actual['gpu_dependency_hashes']
        if actual['execution_mode']!='in_place_record' or 'stream_input' in deps or deps.get('cb')!=fixture['constants']['sha256']:raise ValueError('NOT_OWN_WATER_ALIAS')
        if identity(out/'raw'/(case['case_id']+'_cb_before.bin'))['sha256']!=fixture['constants']['sha256']:raise ValueError('GODOT_CONSTANTS_PROOF')
        for slot,a in enumerate(fixture['srvs']):
            key='texture' if event==1537 and slot==0 else 'auxiliary';suffix='texture_before' if key=='texture' else 'aux_before'
            if deps.get(key)!=a['sha256'] or identity(out/'raw'/(case['case_id']+'_'+suffix+'.bin'))['sha256']!=a['sha256']:raise ValueError('GODOT_AUXILIARY_PROOF')
        if len(actual['repeats'])!=3:raise ValueError('GODOT_CAPTURE_COVERAGE')
        for r in actual['repeats']:
            before=identity(out/'raw'/(case['case_id']+'_'+str(r['index'])+'_before.bin'));normal=identity(r['after']);stream=identity(out/'raw'/(case['case_id']+'_'+str(r['index'])+'_stream_output.bin'))
            if before['sha256']!=fixture['input']['sha256'] or r['before_sha256']!=before['sha256'] or normal['size_bytes']!=2097152 or stream['size_bytes']!=stream_bytes:raise ValueError('GODOT_CAPTURE_EXTENT_OR_INPUT')
            if not r['submit_begin_usec']<=r['sync_begin_usec']<=r['sync_end_usec']:raise ValueError('GODOT_COMPLETION_BRACKET')
            stream_valid(stream['path']);target=out/'native'/('replay_'+str(r['index']));kind='floor' if event==1484 else 'sources' if event==1537 else 'simple'
            command=[str(out/'sources/water_readstream_reference.exe'),'--program',replay['program']['path'],'--input',fixture['input']['path'],'--constants',fixture['constants']['path'],'--kind',kind,'--stream-input',stream['path'],'--before-copy','1','--repeat','1','--output',str(target)]
            if kind=='floor':command+=['--srv0',fixture['srvs'][0]['path']]
            if kind=='sources':command+=['--texture0',fixture['srvs'][0]['path'],'--srv1',fixture['srvs'][1]['path']]
            if run('native_'+str(r['index']),command):raise ValueError('NATIVE_ALIAS_STREAM_REPLAY_FAILED')
            log=json.loads((target/'execution.jsonl').read_text().splitlines()[0]);native=identity(target/'after_0.bin');native_stream=identity(target/'stream_0.bin')
            if identity(target/'before_0.bin')['sha256']!=fixture['input']['sha256'] or identity(target/'srv2_before_0.bin')['sha256']!=stream['sha256'] or log['fence_completed']<log['fence_ticket']:raise ValueError('NATIVE_REPLAY_COMPLETION_OR_INPUT')
            for slot,a in enumerate(fixture['srvs']):
                if identity(target/f'srv{slot}_before_0.bin')['sha256']!=a['sha256']:raise ValueError('NATIVE_REPLAY_AUXILIARY_PROOF')
            norm_diff=int(np.count_nonzero(np.fromfile(native['path'],dtype='<u4')!=np.fromfile(normal['path'],dtype='<u4')));record_diff=int(np.count_nonzero(np.fromfile(native_stream['path'],dtype='<u4')!=np.fromfile(stream['path'],dtype='<u4')))
            report['records'].append(dict(repeat=r['index'],before=before,godot_normal=normal,godot_stream=stream,native_normal=native,native_stream=native_stream,normal_word_mismatches=norm_diff,stream_word_mismatches=record_diff,native_fence_complete=True))
            if norm_diff or record_diff:report['errors'].append(dict(repeat=r['index'],normal=norm_diff,stream=record_diff))
            save();print(json.dumps(dict(event=event,repeat=r['index'],normal=norm_diff,stream=record_diff)),flush=True)
        report['gpu_result']=result
        if args.guard_reference:
            prior=json.loads(args.guard_reference.read_text())
            if prior['verification_status']!='passed' or prior['guard_probe_sha256']!=lower['probe']['sha256'] or len(prior['guards'])!=3 or not all(g['passed'] for g in prior['guards']):raise ValueError('GUARD_REUSE_NOT_VALID')
            report['guards']=[dict(case=g['case'],passed=True,reused_from=identity(args.guard_reference)) for g in prior['guards']]
        else:
            for name,expected in [('bad_read_count','READ_STREAM_PILOT_MODE_REQUIRED'),('unexpected_stream','UNEXPECTED_STREAM_INPUT_FOR_RECORD'),('missing_replay_stream','STREAM_INPUT_REQUIRED_FOR_REPLAY')]:
                bad=json.loads(json.dumps(case));target=out/'guards'/name;target.mkdir()
                if name=='bad_read_count':bad['read_count']+=1
                elif name=='unexpected_stream':bad['stream_input']=reference['capture']['checks'][0]['stream']
                else:bad['execution_mode']='read_stream'
                q=out/'guards'/(name+'.json');q.write_text(json.dumps(dict(schema_version='1.0',repeat_count=1,output_root=str(target),cases=[bad]),indent=2),encoding='utf-8')
                code=run('guard_'+name,godot_command(q,name));outcome=json.loads((target/'probe_result.json').read_text());passed=code!=0 and outcome['operation_status']=='failed' and outcome['local_device_released'] and any(expected in x for x in outcome['errors'])
                report['guards'].append(dict(case=name,expected=expected,result=outcome,passed=passed))
                if not passed:report['errors'].append('GUARD_NOT_REJECTED:'+name)
        report['operation_status']='complete';report['verification_status']='failed' if report['errors'] else 'passed'
    except Exception as error:
        report['operation_status']='failed';report['errors'].append(str(error))
    report['artifacts']=[identity(p) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json'];save()
    print(json.dumps(dict(status=report['verification_status'],event=event,records=len(report['records']),errors=report['errors'])),flush=True);raise SystemExit(bool(report['errors']))


if __name__=='__main__':main()
