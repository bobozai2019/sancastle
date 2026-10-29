"""Short owned-copy startup with process-local isolation installed before resume."""
import argparse
import ctypes
import datetime
import hashlib
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

def snapshot_tree(root):
    return dict(root=str(root),exists=root.exists(),files=[dict(**identity(p),mtime_ns=p.stat().st_mtime_ns) for p in sorted(root.rglob('*')) if p.is_file()] if root.exists() else [])

def registry_snapshot(path):
    rows=[]
    def walk(key,prefix):
        i=0
        while True:
            try:name,value,kind=winreg.EnumValue(key,i)
            except OSError:break
            raw=value if isinstance(value,bytes) else json.dumps(value,ensure_ascii=True).encode()
            rows.append(dict(key=prefix,name=name,type=kind,value_sha256=hashlib.sha256(raw).hexdigest()));i+=1
        i=0
        while True:
            try:name=winreg.EnumKey(key,i)
            except OSError:break
            with winreg.OpenKey(key,name) as child:walk(child,prefix+'\\'+name)
            i+=1
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,path) as key:walk(key,path)
        return dict(path=path,exists=True,values=rows)
    except FileNotFoundError:return dict(path=path,exists=False,values=[])

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',required=True,type=Path);ap.add_argument('--seconds',type=float,default=15)
    ap.add_argument('--observer',type=Path)
    ap.add_argument('--shadow-every',type=int,default=0,help='Pilot-only full state shadow every N water dispatches; 0 disables')
    ap.add_argument('--clock-sample-every',type=int,default=0,help='Read-only Unity Time getters every N source calls; 0 disables')
    ap.add_argument('--native-scalars',action='store_true',help='Use tested native x64 XMM scalar listeners/cache; requires observer')
    ap.add_argument('--detach-water-at',type=float,help='Diagnostic only: close/drain/detach only water hooks at this second; common guard/Present remain')
    ap.add_argument('--hook-schedule',help='Diagnostic only, e.g. 16:off,26:on,46:off; discarded as a formal continuous parameter trajectory')
    ap.add_argument('--present',action='store_true',help='Common DXGI Present timing in every compared mode')
    ap.add_argument('--renderdoc',action='store_true',help='External injection after guard readiness, before resume')
    ap.add_argument('--capture-at',type=float,help='Request one next-Present capture at this second after resume')
    ap.add_argument('--seed-user-data',action='store_true',help='Copy opaque user files into the private run; never interpret save/profile content')
    args=ap.parse_args();out=args.output.resolve()
    if not str(out).isascii() or not 1<=args.seconds<=60:raise ValueError('ASCII output, 1..60 seconds required')
    if args.capture_at is not None and (not args.renderdoc or not 0<args.capture_at<args.seconds-5):raise ValueError('Capture requires RenderDoc and at least 5 seconds remaining')
    if args.shadow_every<0 or (args.shadow_every and not args.observer):raise ValueError('Shadow requires an observer and nonnegative interval')
    if args.clock_sample_every<0 or (args.clock_sample_every and not args.observer):raise ValueError('Clock sampling requires observer and nonnegative interval')
    if args.native_scalars and not args.observer:raise ValueError('Native scalar cache requires observer')
    if args.detach_water_at is not None and (not args.observer or not 0<args.detach_water_at<args.seconds-5):raise ValueError('Diagnostic detach requires observer and at least 5 seconds remaining')
    schedule=[]
    if args.hook_schedule:
        if not args.observer or args.detach_water_at is not None:raise ValueError('Schedule requires observer, cannot combine detach-at')
        previous=0;expected='off'
        for item in args.hook_schedule.split(','):
            value,action=item.split(':');value=float(value)
            if not previous<value<args.seconds-3 or action!=expected:raise ValueError('Ordered alternating off/on schedule required')
            schedule.append((value,action));previous=value;expected='on' if action=='off' else 'off'
    game=ROOT/'task/competitor_water_solver_evidence/work/runtime_game_v1'
    exe=game/'Sandcastle.exe'
    if identity(exe)['sha256']!='355c19485e69c82bba3b15ed8e936fa290e61a474c73463b1bfa2ce6da8bf2a4':raise ValueError('Copy identity mismatch')
    out.mkdir(parents=True,exist_ok=False)
    for name in ['sources','logs','profile','local','local_low','roaming','temp','registry','rdc']:(out/name).mkdir()
    shutil.copyfile(__file__,out/'sources/runtime_startup.py')
    guard=Path(__file__).parent/'runtime/isolation_guard.js'
    shutil.copyfile(guard,out/'sources/isolation_guard.js')
    watched=[Path(os.environ['USERPROFILE'])/'AppData/LocalLow/BubblebirdStudio/Sandcastle',Path(os.environ['LOCALAPPDATA'])/'BubblebirdStudio/Sandcastle',Path(os.environ['APPDATA'])/'BubblebirdStudio/Sandcastle']
    def before_after():return dict(user_data=[snapshot_tree(p) for p in watched],registry=registry_snapshot(r'Software\BubblebirdStudio\Sandcastle'),game=snapshot_tree(game))
    before=before_after();(out/'before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    volumes={}
    for letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
        b=ctypes.create_unicode_buffer(32768)
        if ctypes.windll.kernel32.QueryDosDeviceW(letter+':',b,32768):volumes[b.value]=letter+':'
    cfg=dict(allowed_roots=[str(out)],volumes=volumes,hive=str(out/'registry/current_user.hiv'),**{n:str(out/n) for n in ['profile','local','local_low','roaming']})
    cfg['path_redirects']=[dict(from_=str(p),to=str(out/n/'BubblebirdStudio/Sandcastle')) for p,n in zip(watched,['local_low','local','roaming'])]
    cfg['path_redirects']=[{'from':m['from_'],'to':m['to']} for m in cfg['path_redirects']]
    for m in cfg['path_redirects']:Path(m['to']).mkdir(parents=True,exist_ok=True)
    seeded=[]
    if args.seed_user_data:
        for src,m in zip(watched,cfg['path_redirects']):
            if not src.exists():continue
            for file in src.rglob('*'):
                if file.is_symlink() or file.is_junction():raise ValueError('User data reparse point rejected')
                if not file.is_file():continue
                dest=Path(m['to'])/file.relative_to(src);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(file,dest)
                seeded.append(dict(source=identity(file),copy=identity(dest)))
    (out/'seed_manifest.json').write_text(json.dumps(dict(opaque_copy_only=True,files=seeded),indent=2),encoding='utf-8')
    cfg['folder_guids']={uuid.UUID(g).bytes_le.hex():cfg[k] for g,k in [('A520A1A4-1780-4FF6-BD18-167343C5AF16','local_low'),('F1B32785-6FBA-4FCF-9D55-7B8E7F157091','local'),('3EB685DB-65F9-4CF6-A03A-E3EF65729F3D','roaming'),('5E6C858F-0E22-4760-9AFE-EA3317B67173','profile')]}
    (out/'config.json').write_text(json.dumps(cfg,indent=2),encoding='utf-8')
    env=dict(os.environ,USERPROFILE=cfg['profile'],LOCALAPPDATA=cfg['local'],APPDATA=cfg['roaming'],TEMP=str(out/'temp'),TMP=str(out/'temp'))
    command=[str(exe),'-force-d3d12','-screen-fullscreen','0','-screen-width','960','-screen-height','540','-logFile',str(out/'logs/Player.log')]
    events=[];outputs=[];detached=[];errors=[];pid=None;session=None;script=None;observer=None;presenter=None;capture=None;initial=None;final=None;observer_final=None;presentation_final=None;capture_final=None;capture_requested=False;injection=None
    device=frida.get_local_device();device.on('output',lambda p,f,d:outputs.append(dict(pid=p,fd=f,data=d.decode(errors='replace'))))
    started=datetime.datetime.now(datetime.timezone.utc).isoformat();resume_at=None;elapsed=None;water_detached=False;schedule_index=0
    try:
        pid=device.spawn(command,cwd=str(game),env=env,stdio='pipe')
        session=device.attach(pid);session.on('detached',lambda *a:detached.append([str(x) for x in a]))
        script=session.create_script('globalThis.ISOLATION_CONFIG='+json.dumps(cfg)+';\n'+guard.read_text())
        script.on('message',lambda m,d:events.append(m));script.load();initial=script.exports_sync.isolationstatus()
        if not initial['ready'] or initial['errors']:raise RuntimeError('ISOLATION_NOT_READY:'+str(initial))
        if args.renderdoc:
            rd=Path('D:/other_software/RenderDoc/renderdoccmd.exe');launch=[str(rd),'inject','--PID='+str(pid),'-c',str(out/'rdc/water')]
            begin=time.monotonic();result=subprocess.run(launch,capture_output=True,timeout=25,env=env,cwd=out)
            (out/'logs/inject_stdout.bin').write_bytes(result.stdout);(out/'logs/inject_stderr.bin').write_bytes(result.stderr)
            injection=dict(command=launch,exit_code=result.returncode,elapsed_seconds=time.monotonic()-begin,tool=identity(rd),dll=identity(rd.with_name('renderdoc.dll')),header=identity(rd.with_name('renderdoc_app.h')))
            (out/'injection.json').write_text(json.dumps(injection,indent=2),encoding='utf-8')
            match=re.search(rb'Launched as ID (\d+)',result.stdout+result.stderr)
            if not match or int(match.group(1))!=result.returncode:raise RuntimeError('RENDERDOC_INJECTION_FAILED')
            source=Path(__file__).parent/'runtime/renderdoc_control.js';shutil.copyfile(source,out/'sources/renderdoc_control.js')
            capture=session.create_script('globalThis.CAPTURE_CONFIG='+json.dumps(dict(prefix=str(out/'rdc/water')))+';\n'+source.read_text());capture.on('message',lambda m,d:events.append(m));capture.load()
        if args.present:
            source=Path(__file__).parent/'runtime/presentation_observer.js';shutil.copyfile(source,out/'sources/presentation_observer.js')
            (out/'dxgi_header_identity.json').write_text(json.dumps(identity(Path('C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/shared/dxgi1_2.h')),indent=2),encoding='utf-8')
            presenter=session.create_script(source.read_text());presenter.on('message',lambda m,d:events.append(m));presenter.load()
        if args.observer:
            shutil.copyfile(args.observer,out/'sources/water_observer.js')
            prefix=''
            if args.native_scalars:
                for name in ['scalar_bridge.c','scalar_bridge.js']:shutil.copyfile(Path(__file__).parent/'runtime'/name,out/'sources'/name)
                prefix='globalThis.SCALAR_BRIDGE_SOURCE='+json.dumps((out/'sources/scalar_bridge.c').read_text())+';\n'+(out/'sources/scalar_bridge.js').read_text()+'\n'
            observer=session.create_script(prefix+'globalThis.TRACE_CONFIG='+json.dumps(dict(shadow_every=args.shadow_every,clock_sample_every=args.clock_sample_every,native_scalars=args.native_scalars))+';\n'+args.observer.read_text());observer.on('message',lambda m,d:events.append(m));observer.load()
        if presenter:
            begin=time.monotonic_ns();mark=presenter.exports_sync.mark('before_resume');events.append(dict(type='host',payload=dict(kind='qpc_calibration',begin_monotonic_ns=str(begin),end_monotonic_ns=str(time.monotonic_ns()),marker=mark)))
        resume_at=time.monotonic();device.resume(pid)
        while not detached and time.monotonic()-resume_at<args.seconds:
            if schedule_index<len(schedule) and time.monotonic()-resume_at>=schedule[schedule_index][0]:
                scheduled_at,action=schedule[schedule_index]
                if action=='off':
                    observer_final=observer.exports_sync.finish();deadline=time.monotonic()+2
                    while observer_final['inflight'] and time.monotonic()<deadline:
                        time.sleep(.02);observer_final=observer.exports_sync.status()
                    if observer_final['inflight']:raise RuntimeError('DIAGNOSTIC_CALLS_NOT_DRAINED')
                    if presenter:presenter.exports_sync.mark('schedule_off_before_'+str(schedule_index))
                    observer_final=observer.exports_sync.detachhot();water_detached=True
                else:
                    if presenter:presenter.exports_sync.mark('schedule_on_before_'+str(schedule_index))
                    observer_final=observer.exports_sync.attachhot();water_detached=False
                if presenter:presenter.exports_sync.mark('schedule_'+action+'_after_'+str(schedule_index))
                schedule_index+=1
            if observer and args.detach_water_at is not None and not water_detached and time.monotonic()-resume_at>=args.detach_water_at:
                observer_final=observer.exports_sync.finish();deadline=time.monotonic()+2
                while observer_final['inflight'] and time.monotonic()<deadline:
                    time.sleep(.02);observer_final=observer.exports_sync.status()
                if observer_final['inflight']:raise RuntimeError('DIAGNOSTIC_CALLS_NOT_DRAINED')
                if presenter:presenter.exports_sync.mark('water_detach_before')
                observer_final=observer.exports_sync.detachhot();water_detached=True
                if presenter:presenter.exports_sync.mark('water_detach_after')
            if capture and args.capture_at is not None and not capture_requested and time.monotonic()-resume_at>=args.capture_at:
                if presenter:presenter.exports_sync.mark('capture_request_before')
                request_begin=time.monotonic_ns();requested=capture.exports_sync.trigger();capture_requested=True
                events.append(dict(type='host',payload=dict(kind='capture_requested',begin_monotonic_ns=str(request_begin),end_monotonic_ns=str(time.monotonic_ns()),result=requested)))
                if presenter:presenter.exports_sync.mark('capture_request_after')
            time.sleep(.1)
        elapsed=time.monotonic()-resume_at
        if not detached:
            if observer:
                observer_final=observer.exports_sync.finish()
                deadline=time.monotonic()+2
                while observer_final['inflight'] and time.monotonic()<deadline:
                    time.sleep(.02);observer_final=observer.exports_sync.status()
                time.sleep(.15)
            final=script.exports_sync.isolationstatus()
            if presenter:
                presentation_final=presenter.exports_sync.finish();deadline=time.monotonic()+2
                while presentation_final['inflight'] and time.monotonic()<deadline:
                    time.sleep(.02);presentation_final=presenter.exports_sync.status()
                time.sleep(.15)
            if capture:capture_final=capture.exports_sync.status()
        else:errors.append('PROCESS_EXITED_DURING_STARTUP')
    except Exception as exc:errors.append(str(exc))
    finally:
        if pid is not None and not detached:
            try:device.kill(pid)
            except frida.ProcessNotFoundError:pass
        if session:
            try:session.detach()
            except frida.InvalidOperationError:pass
    after=before_after();(out/'after.json').write_text(json.dumps(after,indent=2),encoding='utf-8')
    (out/'logs/events.json').write_text(json.dumps(events,indent=2),encoding='utf-8')
    (out/'logs/process_output.json').write_text(json.dumps(outputs,indent=2),encoding='utf-8')
    (out/'observer_final.json').write_text(json.dumps(observer_final,indent=2),encoding='utf-8')
    (out/'presentation_final.json').write_text(json.dumps(presentation_final,indent=2),encoding='utf-8')
    (out/'capture_final.json').write_text(json.dumps(capture_final,indent=2),encoding='utf-8')
    (out/'mode.json').write_text(json.dumps(dict(water_observer=args.observer is not None,presentation_observer=args.present,renderdoc=args.renderdoc,capture_at=args.capture_at,shadow_every=args.shadow_every,clock_sample_every=args.clock_sample_every,native_scalars=args.native_scalars,detach_water_at=args.detach_water_at,hook_schedule=schedule,formal_eligible=not args.shadow_every and args.detach_water_at is None and not schedule,host_command=sys.argv,comparison_scope='All modes include the same process-local isolation; baseline means no water observer'),indent=2),encoding='utf-8')
    unchanged=before==after
    player=out/'logs/Player.log'
    engine_initialized=player.exists() and 'Initialize engine version:' in player.read_text(encoding='utf-8',errors='replace')
    if not engine_initialized:errors.append('ENGINE_INITIALIZATION_UNCONFIRMED')
    if not unchanged:errors.append('WATCHED_SOURCE_OR_USER_DATA_CHANGED')
    if args.present and (not presentation_final or not presentation_final['presents']):errors.append('PRESENT_UNOBSERVED')
    if args.capture_at is not None and (not capture_final or capture_final['count']!=1):errors.append('CAPTURE_NOT_COMPLETED')
    manifest=dict(operation_status='complete' if not errors else 'failed',verification_status='partial',engine_initialized=engine_initialized,scope='Owned startup only; engine/API/GPU consumption and perturbation not established',started_at=started,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),command=command,pid=pid,owned_stop='Frida kill of spawned PID only',frida_version=frida.__version__,resumed=resume_at is not None,elapsed_seconds=elapsed,initial_isolation=initial,final_isolation=final,watched_source_and_user_data_unchanged=unchanged,errors=errors,termination=detached,artifacts=[identity(p) for p in out.rglob('*') if p.is_file()])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps({k:manifest[k] for k in ['operation_status','pid','resumed','elapsed_seconds','watched_source_and_user_data_unchanged','errors']}),flush=True)
    raise SystemExit(1 if errors else 0)

if __name__=='__main__':main()
