"""Owned process only; preserve messages and raw API bytes without fake success."""
import argparse, sys, json, time, hashlib, subprocess, datetime
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE/'deps'))
import frida
from baseline import identity, save
def process_identity(pid):
    assert isinstance(pid,int) and pid>0
    cmd="$p=Get-CimInstance Win32_Process -Filter 'ProcessId="+str(pid)+"'; if ($p) { [pscustomobject]@{pid=$p.ProcessId;path=$p.ExecutablePath;created_utc=$p.CreationDate.ToUniversalTime().ToString('o')} | ConvertTo-Json -Compress }"
    data=subprocess.check_output(['powershell','-NoProfile','-Command',cmd],text=True).strip()
    return json.loads(data) if data else None
def main():
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--seconds',type=int,default=45);p.add_argument('--agent',default=str(HERE/'probe_agent.js'));p.add_argument('--dynamic',action='store_true');p.add_argument('--attach-owner');p.add_argument('--chunk');p.add_argument('--keep-process',action='store_true');p.add_argument('--force-d3d11',action='store_true');p.add_argument('--aux',action='store_true');p.add_argument('--controlled',action='store_true');a=p.parse_args()
    run=Path(a.run).resolve(); attempt=run/('attempt_'+datetime.datetime.now().strftime('%H%M%S'));attempt.mkdir(exist_ok=False)
    exe=run/'owned_game/Sandcastle.exe'
    expected=json.loads((run/'copy_manifest.json').read_text(encoding='utf8'))
    for row in expected:
        assert identity(row['copy']['path'])['sha256']==row['copy']['sha256'],row['copy']['path']
    dev=frida.get_local_device();session=None;pid=None;script=None;received=[];owned_identity=None
    argv=[str(exe),'-screen-fullscreen','0','-screen-width','960','-screen-height','540','-logFile',str(attempt/'player.log')]
    if a.force_d3d11:argv.append('-force-d3d11')
    save(attempt/'tool_manifest.json',{'frida':frida.__version__,'python':sys.version,'command':sys.argv,'agent':identity(a.agent),'driver':identity(__file__)})
    (attempt/'agent.js').write_bytes(Path(a.agent).read_bytes())
    (attempt/'driver.py').write_bytes(Path(__file__).read_bytes())
    try:
        if a.attach_owner:
            owner=json.loads(Path(a.attach_owner).read_text(encoding='utf8'));assert owner['ownership']=='created by this probe using frida device.spawn'
            assert Path(owner['argv'][0]).resolve()==exe.resolve();pid=owner['pid']
            processes=dev.enumerate_processes();assert any(x.pid==pid and x.name.lower()=='sandcastle.exe' for x in processes),'owned process not live'
            owned_identity=process_identity(pid);assert owned_identity and Path(owned_identity['path']).resolve()==exe.resolve(),'owned executable path mismatch'
            if owner.get('process_identity'):assert owner['process_identity']==owned_identity,'owned process start identity mismatch'
        else:pid=dev.spawn(argv,cwd=str(exe.parent))
        if not a.attach_owner:owned_identity=process_identity(pid)
        if a.attach_owner:
            save(attempt/'owner.json',dict(owner,source_owner_record=str(Path(a.attach_owner).resolve()),attached_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),process_identity=owned_identity))
        else:save(attempt/'owner.json',{'pid':pid,'argv':argv,'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'ownership':'created by this probe using frida device.spawn','process_identity':owned_identity})
        save(attempt/'request.json',{'run_id':run.name,'target_pid':pid,'mode':'owned_runtime','dynamic':a.dynamic,'expected_gameassembly_sha256':identity(exe.parent/'GameAssembly.dll')['sha256'],'expected_metadata_sha256':identity(exe.parent/'Sandcastle_Data/il2cpp_data/Metadata/global-metadata.dat')['sha256'],'max_snapshot_bytes':67108864,'capture_limit_vertices':1000000,'capture_limit_indices':6000000,'trigger':'after_successful_shared_mesh_binding'})
        session=dev.attach(pid)
        def msg(message,data):
            received.append(message)
            record={'received_monotonic_ns':str(time.monotonic_ns()),'message':message}
            if data:
                path=attempt/('raw_'+str(time.monotonic_ns())+'.bin');path.write_bytes(data);record['raw']=identity(path)
            with (attempt/'messages.jsonl').open('a',encoding='utf8') as f:f.write(json.dumps(record)+'\n')
            payload=message.get('payload',{});summary={k:payload[k] for k in ['kind','snapshot_id','payload_kind','vertex_count','code','message'] if k in payload}
            if message['type']=='error':summary={'kind':'script_error','message':message.get('description')}
            if payload.get('kind')!='input_physics' or payload.get('left_button_pressed') is True:print(json.dumps(summary),flush=True)
        source='globalThis.PROBE_DYNAMIC='+json.dumps(a.dynamic)+';globalThis.PROBE_TARGET='+json.dumps(a.chunk)+';globalThis.PROBE_AUX='+json.dumps(a.aux)+';globalThis.PROBE_CONTROLLED='+json.dumps(a.controlled)+';\n'+Path(a.agent).read_text(encoding='utf8')
        (attempt/'agent.js').write_text(source,encoding='utf8')
        script=session.create_script(source);script.on('message',msg);script.load()
        if not a.attach_owner:
            dev.resume(pid)
            resumed_identity=process_identity(pid)
            assert resumed_identity and Path(resumed_identity['path']).resolve()==exe.resolve(),'resumed owned executable path mismatch'
            assert owned_identity and resumed_identity['pid']==owned_identity['pid'] and resumed_identity['created_utc']==owned_identity['created_utc'],'owned process start changed at resume'
            owned_identity=resumed_identity
            save(attempt/'resumed_process_identity.json',owned_identity)
        deadline=time.monotonic()+a.seconds
        armed=False;phase_request=None
        while time.monotonic()<deadline and not session.is_detached:
            if (attempt/'stop.json').exists():break
            if a.dynamic and not armed and (attempt/'arm_edit.json').exists():
                script.exports_sync.arm();armed=True
            if a.controlled and (attempt/'capture_request.json').exists():
                request=json.loads((attempt/'capture_request.json').read_text(encoding='utf-8-sig'))
                if request['request_id']!=phase_request:
                    script.exports_sync.phase(request['phase']);phase_request=request['request_id']
            time.sleep(.25)
        save(attempt/'observation_end.json',{'detached':session.is_detached,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()})
    except Exception as e:
        save(attempt/'failure.json',{'type':type(e).__name__,'message':str(e)});raise
    finally:
        if session and not session.is_detached:
            if script:script.unload()
            session.detach()
        if pid and not a.keep_process and not a.attach_owner:
            try:
                current=process_identity(pid)
                if current is None:save(attempt/'cleanup.json',{'owned_pid':pid,'cleanup':'already terminal'})
                elif current==owned_identity:dev.kill(pid);save(attempt/'cleanup.json',{'owned_pid':pid,'kill':'success','checked_identity':current})
                else:save(attempt/'cleanup.json',{'owned_pid':pid,'cleanup':'PID start identity changed; current process preserved'})
            except Exception as e:save(attempt/'cleanup.json',{'owned_pid':pid,'kill_error':str(e)})
        elif pid:save(attempt/'cleanup.json',{'owned_pid':pid,'cleanup':'detached; process lifetime controlled by original spawn owner'})
    print('attempt='+str(attempt),flush=True)
    payloads=[x.get('payload',{}) for x in received]
    success=any(x.get('kind') in ['snapshot','collider_identity_map'] or x.get('kind')=='getter_sample' and x.get('same_mesh') for x in payloads)
    errors=any(x['type']=='error' or x.get('payload',{}).get('kind') in ['error','locator_error'] for x in received)
    partial=success or any(x.get('kind')=='raw' for x in payloads)
    return 0 if success and not errors else 2 if partial else 3
if __name__=='__main__':sys.exit(main())
