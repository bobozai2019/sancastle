"""Test native scalar forwarding on an owned C++ helper before any game integration."""
import argparse
import ctypes
import datetime
import json
import os
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path
from evidence_contract import identity
sys.dont_write_bytecode=True
ROOT=Path('D:/godot/project/sandcastle')
sys.path.insert(0,str(ROOT/'tests/investigation/brush_hit_competitor/runtime_collider/deps'))
import frida

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',required=True,type=Path);ap.add_argument('--capacity',type=int,default=64);ap.add_argument('--expect-overflow',action='store_true');ap.add_argument('--baseline',action='store_true');args=ap.parse_args();out=args.output.resolve()
    if not str(out).isascii() or args.capacity<2 or args.capacity>8192 or args.capacity&(args.capacity-1):raise ValueError('ASCII path and power-of-two capacity 2..8192 required')
    out.mkdir(parents=True,exist_ok=False)
    for n in ['sources','logs','profile','local','local_low','roaming','temp','registry']:(out/n).mkdir()
    here=Path(__file__).parent
    for name in ['isolation_guard.js','scalar_bridge.c','scalar_bridge.js','scalar_probe.cpp']:shutil.copyfile(here/'runtime'/name,out/'sources'/name)
    shutil.copyfile(__file__,out/'sources/probe_scalar_bridge.py');shutil.copyfile(here/'evidence_contract.py',out/'sources/evidence_contract.py')
    exe=out/'sources/scalar_probe.exe';batch=out/'sources/build.cmd'
    batch.write_text('@echo off\ncall "D:\\IDE_SOFTWARE\\vs\\VC\\Auxiliary\\Build\\vcvars64.bat"\nif errorlevel 1 exit /b %errorlevel%\ncl /nologo /EHsc /std:c++17 /Od "'+str(out/'sources/scalar_probe.cpp')+'" /Fe:"'+str(exe)+'" /Fo:"'+str(out/'sources/scalar_probe.obj')+'"\nexit /b %errorlevel%\n',encoding='ascii')
    result=subprocess.run(['cmd.exe','/d','/c',str(batch)],cwd=out,capture_output=True)
    (out/'logs/build_stdout.bin').write_bytes(result.stdout);(out/'logs/build_stderr.bin').write_bytes(result.stderr)
    if result.returncode:raise RuntimeError(result.stdout.decode(errors='replace')+result.stderr.decode(errors='replace'))
    volumes={}
    for letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
        buf=ctypes.create_unicode_buffer(32768)
        if ctypes.windll.kernel32.QueryDosDeviceW(letter+':',buf,32768):volumes[buf.value]=letter+':'
    cfg=dict(allowed_roots=[str(out)],volumes=volumes,hive=str(out/'registry/current_user.hiv'),**{n:str(out/n) for n in ['profile','local','local_low','roaming']})
    cfg['folder_guids']={uuid.UUID(g).bytes_le.hex():cfg[k] for g,k in [('A520A1A4-1780-4FF6-BD18-167343C5AF16','local_low'),('F1B32785-6FBA-4FCF-9D55-7B8E7F157091','local'),('3EB685DB-65F9-4CF6-A03A-E3EF65729F3D','roaming'),('5E6C858F-0E22-4760-9AFE-EA3317B67173','profile')]}
    (out/'config.json').write_text(json.dumps(cfg,indent=2),encoding='utf-8')
    bridge='globalThis.SCALAR_BRIDGE_SOURCE='+json.dumps((out/'sources/scalar_bridge.c').read_text())+';\n'+(out/'sources/scalar_bridge.js').read_text()+"\nconst main=Process.getModuleByName('scalar_probe.exe'),bridge=makeScalarBridge(main.getExportByName('probe_compute'),main.getExportByName('probe_global'),"+str(args.capacity)+");Interceptor.attach(main.getExportByName('probe_compute'),{onEnter:bridge.computeEnter});Interceptor.attach(main.getExportByName('probe_global'),{onEnter:bridge.globalEnter});Interceptor.attach(main.getExportByName('probe_done'),{onEnter(){send({kind:'scalar_bridge_result',rows:bridge.drain(),counters:bridge.status()});}});send({kind:'scalar_bridge_ready',platform:Process.platform,arch:Process.arch,pointer_size:Process.pointerSize});"
    (out/'sources/probe_agent.js').write_text(bridge,encoding='utf-8')
    checkpoint="const last=new Map();let checkpoints=0,checkpointMismatches=0;function collect(){for(const row of bridge.drain())last.set(row.kind+':'+row.object+':'+row.property_id,row);}Interceptor.attach(main.getExportByName('probe_checkpoint'),{onEnter(a){collect();checkpoints++;const index=a[0].toInt32(),bits=a[1].toUInt32(),object=String(a[2]),c=last.get('1:'+object+':857'),g=last.get('2:0x0:'+(1000+index));if(!c||!g||c.value_bits!==bits||g.value_bits!==bits)checkpointMismatches++;}});"
    bridge=bridge.replace("Interceptor.attach(main.getExportByName('probe_done'),",checkpoint+"Interceptor.attach(main.getExportByName('probe_done'),").replace("send({kind:'scalar_bridge_result',rows:bridge.drain(),counters:bridge.status()});","collect();send({kind:'scalar_bridge_result',rows:Array.from(last.values()),counters:bridge.status(),checkpoints,checkpoint_mismatches:checkpointMismatches});")
    (out/'sources/probe_agent.js').write_text(bridge,encoding='utf-8')
    if args.baseline:
        bridge=bridge.replace("Interceptor.attach(main.getExportByName('probe_compute'),{onEnter:bridge.computeEnter});Interceptor.attach(main.getExportByName('probe_global'),{onEnter:bridge.globalEnter});",'')
        (out/'sources/probe_agent.js').write_text(bridge,encoding='utf-8')
    events=[];output=[];detached=[];errors=[];pid=None;session=None;process_handle=None;exit_code=None
    device=frida.get_local_device();device.on('output',lambda p,f,d:output.append(dict(pid=p,fd=f,data=d.decode(errors='replace'))))
    env=dict(os.environ,USERPROFILE=cfg['profile'],LOCALAPPDATA=cfg['local'],APPDATA=cfg['roaming'],TEMP=str(out/'temp'),TMP=str(out/'temp'))
    started=datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        pid=device.spawn([str(exe)],cwd=str(out),env=env,stdio='pipe')
        open_process=ctypes.windll.kernel32.OpenProcess;open_process.restype=ctypes.c_void_p;process_handle=open_process(0x101000,False,pid)
        session=device.attach(pid);session.on('detached',lambda *a:detached.append([str(v) for v in a]))
        guard=session.create_script('globalThis.ISOLATION_CONFIG='+json.dumps(cfg)+';\n'+(out/'sources/isolation_guard.js').read_text());guard.on('message',lambda m,d:events.append(m));guard.load();state=guard.exports_sync.isolationstatus()
        if not state['ready'] or state['errors']:raise RuntimeError('GUARD_NOT_READY')
        script=session.create_script(bridge);script.on('message',lambda m,d:events.append(m));script.load();device.resume(pid)
        deadline=time.monotonic()+30
        while not detached and time.monotonic()<deadline:time.sleep(.02)
        if not detached:raise RuntimeError('SCALAR_PROBE_TIMEOUT')
    except Exception as exc:errors.append(str(exc))
    finally:
        if pid is not None and not detached:
            try:device.kill(pid)
            except frida.ProcessNotFoundError:pass
        if process_handle:
            code=ctypes.c_ulong();get=ctypes.windll.kernel32.GetExitCodeProcess;get.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_ulong)]
            if get(process_handle,ctypes.byref(code)):exit_code=code.value
            ctypes.windll.kernel32.CloseHandle.argtypes=[ctypes.c_void_p];ctypes.windll.kernel32.CloseHandle(process_handle)
        if session:
            try:session.detach()
            except frida.InvalidOperationError:pass
    (out/'logs/events.json').write_text(json.dumps(events,indent=2),encoding='utf-8');(out/'logs/output.json').write_text(json.dumps(output,indent=2),encoding='utf-8')
    try:native=json.loads(''.join(r['data'] for r in output if r['fd']==1).strip())
    except Exception:native=None;errors.append('NO_NATIVE_RESULT')
    result=next((m['payload'] for m in events if m.get('payload',{}).get('kind')=='scalar_bridge_result'),None)
    if any(m.get('type')=='error' for m in events):errors.append('SCRIPT_ERROR')
    if not native or not native['guarded'] or native['failures'] or exit_code!=0:errors.append('NATIVE_FORWARDING_FAILED')
    if not result:errors.append('NO_BRIDGE_RESULT')
    else:
        c=result['counters'];overflow=c['overflow']>0
        if overflow!=args.expect_overflow:errors.append('OVERFLOW_EXPECTATION_MISMATCH')
        expected_calls='0' if args.baseline else '20012'
        if c['compute_calls']!=expected_calls or c['global_calls']!=expected_calls:errors.append('CALL_COUNTS_NOT_CLOSED')
        if not args.expect_overflow and (len(result['rows'])!=(0 if args.baseline else 4) or any(r['value_bits']!=(0x3f800000|9999) for r in result['rows'])):errors.append('LATEST_VALUES_NOT_MATCHED')
        if not args.baseline and not args.expect_overflow and (result.get('checkpoints')!=12 or result.get('checkpoint_mismatches')!=0):errors.append('IEEE754_CHECKPOINT_MISMATCH')
    manifest=dict(operation_status='complete' if not errors else 'failed',verification_status='passed' if not errors else 'failed',scope='Owned two-thread scalar ABI/cache helper only; not Unity/GPU/perturbation validation',started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),host_command=sys.argv,frida_version=frida.__version__,pid=pid,exit_code=exit_code,capacity=args.capacity,expect_overflow=args.expect_overflow,native_result=native,bridge_result=result,errors=errors,artifacts=[identity(p) for p in out.rglob('*') if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print(json.dumps(dict(status=manifest['verification_status'],native=native,counters=result['counters'] if result else None,exit_code=exit_code,errors=errors)))
    raise SystemExit(1 if errors else 0)

if __name__=='__main__':main()
