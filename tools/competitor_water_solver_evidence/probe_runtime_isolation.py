"""Build and spawn an owned test executable; never starts Sandcastle."""
import argparse
import ctypes
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
import winreg
from pathlib import Path
from evidence_contract import identity
sys.dont_write_bytecode=True
ROOT=Path('D:/godot/project/sandcastle')
sys.path.insert(0,str(ROOT/'tests/investigation/brush_hit_competitor/runtime_collider/deps'))
import frida


def registry_present():
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r'Software\CodexWaterSolverEvidence\IsolationProbe'):return True
    except FileNotFoundError:return False


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',required=True,type=Path)
    p.add_argument('--renderdoc-inject',action='store_true',help='Inject RenderDoc into the guarded, still suspended owned helper')
    args=p.parse_args();out=args.output
    if not out.is_absolute() or not str(out).isascii():raise ValueError('Absolute ASCII output required')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','raw','derived','logs','profile','local','roaming','local_low','temp','registry']:(out/name).mkdir()
    tools=Path(__file__).resolve().parent
    for name in ['isolation_probe.cpp','isolation_guard.js']:shutil.copyfile(tools/'runtime'/name,out/'sources'/name)
    shutil.copyfile(__file__,out/'sources/probe_runtime_isolation.py')
    batch=out/'sources/build.cmd';exe=out/'sources/isolation_probe.exe'
    batch.write_text('@echo off\ncall "D:\\IDE_SOFTWARE\\vs\\VC\\Auxiliary\\Build\\vcvars64.bat"\nif errorlevel 1 exit /b %errorlevel%\ncl /nologo /EHsc /std:c++17 "'+str(out/'sources/isolation_probe.cpp')+'" /Fe:"'+str(exe)+'" /Fo:"'+str(out/'sources/isolation_probe.obj')+'" /link shell32.lib ole32.lib advapi32.lib\nexit /b %errorlevel%\n',encoding='ascii')
    built=subprocess.run(['cmd.exe','/d','/c',str(batch)],cwd=out,capture_output=True)
    (out/'logs/build_stdout.bin').write_bytes(built.stdout);(out/'logs/build_stderr.bin').write_bytes(built.stderr)
    if built.returncode:raise RuntimeError(built.stdout.decode(errors='replace')+built.stderr.decode(errors='replace'))
    before=registry_present()
    if before:raise ValueError('Probe registry marker already exists in real HKCU; do not overwrite')
    volumes={}
    for letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
        b=ctypes.create_unicode_buffer(32768)
        if ctypes.windll.kernel32.QueryDosDeviceW(letter+':',b,32768):volumes[b.value]=letter+':'
    cfg=dict(allowed_roots=[str(out)],volumes=volumes,hive=str(out/'registry/current_user.hiv'),
        profile=str(out/'profile'),local=str(out/'local'),local_low=str(out/'local_low'),roaming=str(out/'roaming'))
    alias_path=out.parent/(out.name+'_redirect_alias.txt')
    if alias_path.exists():raise ValueError('Alias test path already exists')
    cfg['path_redirects']=[{'from':str(alias_path),'to':str(out/'raw/redirected.txt')}]
    folder_ids={'A520A1A4-1780-4FF6-BD18-167343C5AF16':'local_low','F1B32785-6FBA-4FCF-9D55-7B8E7F157091':'local',
                '3EB685DB-65F9-4CF6-A03A-E3EF65729F3D':'roaming','5E6C858F-0E22-4760-9AFE-EA3317B67173':'profile'}
    cfg['folder_guids']={uuid.UUID(guid).bytes_le.hex():cfg[key] for guid,key in folder_ids.items()}
    cfg['guid_source']=identity(Path('C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um/KnownFolders.h'))
    (out/'config.json').write_text(json.dumps(cfg,indent=2),encoding='utf-8')
    events=[];output=[];terminated=[];pid=None;session=None;script=None
    device=frida.get_local_device()
    device.on('output',lambda pid,fd,data:output.append(dict(pid=pid,fd=fd,data=data.decode(errors='replace'))))
    env=dict(os.environ,USERPROFILE=cfg['profile'],LOCALAPPDATA=cfg['local'],APPDATA=cfg['roaming'],TEMP=str(out/'temp'),TMP=str(out/'temp'))
    forbidden=out.parent/(out.name+'_outside_denied.txt')
    started=datetime.datetime.now(datetime.timezone.utc).isoformat();errors=[];injection=None
    try:
        pid=device.spawn([str(exe),cfg['local_low'],str(out/'raw/allowed.txt'),str(forbidden),cfg['local'],cfg['roaming'],cfg['profile'],str(alias_path)],cwd=str(out),env=env,stdio='pipe')
        session=device.attach(pid);session.on('detached',lambda *args:terminated.append([str(a) for a in args]))
        script=session.create_script('globalThis.ISOLATION_CONFIG='+json.dumps(cfg)+';\n'+(out/'sources/isolation_guard.js').read_text())
        script.on('message',lambda message,data:events.append(message));script.load()
        status=script.exports_sync.isolationstatus()
        if not status['ready'] or status['errors']:raise ValueError('ISOLATION_NOT_READY:'+str(status))
        if args.renderdoc_inject:
            rd=Path('D:/other_software/RenderDoc/renderdoccmd.exe')
            command=[str(rd),'inject','--PID='+str(pid),'-c',str(out/'raw/helper_capture')]
            begin=time.monotonic();injected=subprocess.run(command,capture_output=True,timeout=25,env=env,cwd=out)
            (out/'logs/inject_stdout.bin').write_bytes(injected.stdout);(out/'logs/inject_stderr.bin').write_bytes(injected.stderr)
            injection=dict(command=command,tool=identity(rd),dll=identity(rd.with_name('renderdoc.dll')),header=identity(rd.with_name('renderdoc_app.h')),elapsed_seconds=time.monotonic()-begin,exit_code=injected.returncode,helper_entry_exists_before_resume=(out/'raw/allowed.txt.entry').exists())
            (out/'injection_before_api.json').write_text(json.dumps(injection,indent=2),encoding='utf-8')
            api_script=session.create_script("rpc.exports={status(){const m=Process.getModuleByName('renderdoc.dll'),p=Memory.alloc(8),get=new NativeFunction(m.getExportByName('RENDERDOC_GetAPI'),'int',['int','pointer'],{exceptions:'propagate'});const result=get(10600,p);return {module:m.path,base:String(m.base),api_result:result};}};")
            api_script.load();loaded=api_script.exports_sync.status()
            injection=dict(command=command,tool=identity(rd),dll=identity(rd.with_name('renderdoc.dll')),header=identity(rd.with_name('renderdoc_app.h')),elapsed_seconds=time.monotonic()-begin,exit_code=injected.returncode,loaded=loaded,helper_entry_exists_before_resume=(out/'raw/allowed.txt.entry').exists())
            match=re.search(rb'Launched as ID (\d+)',injected.stdout+injected.stderr)
            if not match or int(match.group(1))!=injected.returncode or loaded['api_result']!=1 or injection['helper_entry_exists_before_resume']:raise ValueError('INJECTION_PRE_MAIN_CHECK_FAILED')
        device.resume(pid)
        deadline=time.monotonic()+20
        while not terminated and time.monotonic()<deadline:time.sleep(.05)
        if not terminated:raise ValueError('PROBE_TIMEOUT')
    except Exception as error:errors.append(str(error))
    finally:
        if pid is not None and not terminated:
            try:device.kill(pid)
            except frida.ProcessNotFoundError:pass
        if session is not None:
            try:session.detach()
            except frida.InvalidOperationError:pass
    after=registry_present()
    (out/'logs/events.json').write_text(json.dumps(events,indent=2),encoding='utf-8')
    (out/'logs/process_output.json').write_text(json.dumps(output,indent=2),encoding='utf-8')
    text=''.join(r['data'] for r in output if r['fd']==1)
    try:result=json.loads(text.strip())
    except Exception:result=None;errors.append('NO_PROBE_RESULT:'+text)
    if args.renderdoc_inject and result and result.get('renderdoc_api_result')!=1:errors.append('RENDERDOC_NATIVE_HELPER_API_FAILED')
    passed=not errors and not after and not forbidden.exists() and not Path(str(forbidden)+'.renamed').exists() and not alias_path.exists() and (out/'raw/redirected.txt').read_bytes()==b'redirect' and result and result['guard_ready_before_main'] and result['path_redirect_read_write'] and result['folder_correct'] and result['other_folders_correct'] and result['legacy_folders_correct'] and result['outside_write_denied'] and result['rename_within'] and result['rename_outside_denied'] and result['foreign_registry_status']==5 and result['child_denied'] and result['registry_value']==0x57415452
    manifest=dict(operation_status='complete' if not errors else 'failed',verification_status='passed' if passed else 'failed',
        started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),frida_version=frida.__version__,
        pid=pid,termination=terminated,result=result,errors=errors,renderdoc_injection=injection,real_registry_marker_before=before,real_registry_marker_after=after,
        forbidden_file_exists=forbidden.exists(),scope='Owned helper only. Does not prove Unity/bootstrap/child-process/reparse isolation; Sandcastle not launched.',
        artifacts=[identity(p) for p in out.rglob('*') if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(dict(passed=bool(passed),result=result,errors=errors)),flush=True)
    raise SystemExit(0 if passed else 1)


if __name__=='__main__':main()
