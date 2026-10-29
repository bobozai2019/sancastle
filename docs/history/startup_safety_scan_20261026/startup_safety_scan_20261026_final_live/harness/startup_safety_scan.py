"""Scan startup resource hazards and exercise scene construction in Godot.

All generated output and configurable caches stay within the project.
"""
from pathlib import Path
import argparse,os,json,re,subprocess,shutil,hashlib
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
    p.add_argument('--live',action='store_true',help='Also boot, advance and shut down both formal entries twice')
    p.add_argument('--live-only',action='store_true',help='Isolate live startup from the broad detached resource scan')
    p.add_argument('--static-only',action='store_true',help='Run advisory source rules without starting Godot')
    a=p.parse_args();out=a.output.resolve()
    if not out.is_relative_to(ROOT) or out==ROOT:raise SystemExit('Output must be a dedicated directory inside project')
    out.mkdir(parents=True,exist_ok=False)
    harness=out/'harness';harness.mkdir()
    for rel in ['tools/startup_safety_scan.py','tests/integration/startup_resource_scan.gd']:shutil.copy2(ROOT/rel,harness/Path(rel).name)
    env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1'
    for key,name in [('TEMP','tmp'),('TMP','tmp'),('APPDATA','roaming'),('LOCALAPPDATA','local'),('XDG_CACHE_HOME','cache')]:
        d=out/name;d.mkdir(exist_ok=True);env[key]=str(d)
    source=Path(os.environ.get('APPDATA',''))/'Godot/app_userdata/sandcastle/parameters/startup.json'
    parameters=out/'parameters';parameters.mkdir()
    if source.is_file():shutil.copy2(source,parameters/'startup.json')
    else:(parameters/'startup.json').write_text('{"version":1,"scenes":{}}',encoding='utf-8')
    findings=[];resources=sorted([*ROOT.glob('scenes/**/*.tscn'),*ROOT.glob('assets/**/*.tres')])
    for f in resources:
        text=f.read_text(encoding='utf-8-sig');rel=f.relative_to(ROOT).as_posix()
        blocks=list(re.finditer(r'^\[sub_resource\b[^\n]*type="MultiMesh"[^\n]*\n([\s\S]*?)(?=^\[|\Z)',text,re.M))
        if re.search(r'^\[gd_resource\b[^\n]*type="MultiMesh"',text,re.M):
            blocks.extend(re.finditer(r'^\[resource\][^\n]*\n([\s\S]*?)(?=^\[|\Z)',text,re.M))
        for m in blocks:
            block=m[0];count=re.search(r'^instance_count\s*=\s*(\d+)',block,re.M)
            if not count or int(count[1])==0:continue
            if re.search(r'^resource_local_to_scene\s*=\s*true',block,re.M):
                findings.append({'rule':'R001','severity':'risk','file':rel,'line':text[:m.start()].count('\n')+1,'message':'Allocated MultiMesh is scene-local; inspect actual duplication behavior before changing it. This setting alone does not prove a runtime error.'})
            for prop in ['transform_format','use_colors','use_custom_data']:
                setting=re.search(r'^'+prop+r'\s*=',block,re.M)
                if setting and setting.start()>count.start():findings.append({'rule':'R002','severity':'risk','file':rel,'line':text[:m.start()+setting.start()].count('\n')+1,'message':prop+' serialized after nonzero instance_count'})
    scripts=sorted(ROOT.glob('scripts/**/*.gd'))
    text_by_path={f:f.read_text(encoding='utf-8-sig') for f in scripts}
    classes={m[1]:f for f,s in text_by_path.items() if (m:=re.search(r'^class_name\s+(\w+)',s,re.M))}
    def native_base(f,seen=None):
        seen=set() if seen is None else seen
        if f in seen:return ''
        seen.add(f);m=re.search(r'^extends\s+(?:"res://([^"\n]+)"|(\w+))',text_by_path.get(f,''),re.M)
        if not m:return ''
        parent=ROOT/m[1] if m[1] else classes.get(m[2])
        return native_base(parent,seen) if parent in text_by_path else (m[2] or '')
    controls={'Control','Panel','PanelContainer','VBoxContainer','HBoxContainer','ScrollContainer','Label','Button','OptionButton','CheckButton','LineEdit','SpinBox','HSlider','TextureRect','ColorRect'}
    spatial={'Node3D','MeshInstance3D','MultiMeshInstance3D','Camera3D','CharacterBody3D','RigidBody3D','StaticBody3D','Marker3D'}
    for f in scripts:
        text=text_by_path[f];states={};base=native_base(f)
        for n,line in enumerate(text.splitlines(),1):
            if re.match(r'^(?:static )?func ',line):states={}
            code=line.split('#',1)[0]
            for m in re.finditer(r'([\w.]+)\.(instance_count|transform_format|use_colors|use_custom_data)\s*=\s*([^;]+)',code):
                receiver,prop,value=m.groups()
                if prop=='instance_count':states[receiver]=value.strip()!='0'
                elif states.get(receiver,False):findings.append({'rule':'R003','severity':'risk','file':f.relative_to(ROOT).as_posix(),'line':n,'message':'Format setter after possibly nonzero instance_count in same function; branch-sensitive review needed'})
            if re.search(r'\bmultimesh\.duplicate\s*\(',code):findings.append({'rule':'R004','severity':'risk','file':f.relative_to(ROOT).as_posix(),'line':n,'message':'Generic duplication of MultiMesh; verify format-before-allocation semantics'})
            signature=re.search(r'\bfunc\s+\w+\((.*)',code)
            if signature and re.search(r'(?:^|,)\s*hash\s*:',signature[1]):findings.append({'rule':'W001','severity':'warning_candidate','file':f.relative_to(ROOT).as_posix(),'line':n,'message':'Parameter hash shadows global hash(); cosmetic warning, not a startup failure'})
            for var in re.finditer(r'\bvar\s+(material|position)\b',code):
                if (var[1]=='material' and base in controls) or (var[1]=='position' and base in controls|spatial):findings.append({'rule':'W002','severity':'warning_candidate','file':f.relative_to(ROOT).as_posix(),'line':n,'message':var[1]+' shadows an inherited property of '+base+'; review with editor warning location'})
    manifest={'resources':[] if a.live_only else [f'res://{f.relative_to(ROOT).as_posix()}' for f in resources],'scenes':[] if a.live_only else [f'res://{f.relative_to(ROOT).as_posix()}' for f in resources if f.suffix=='.tscn'],'live':a.live or a.live_only}
    source_paths=[*resources,*scripts,*sorted(ROOT.glob('assets/**/*.json')),ROOT/'project.godot']
    before={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in source_paths}
    (out/'source_hashes_before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    (out/'input.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (out/'static.json').write_text(json.dumps({'resource_files':len(resources),'scripts':len(scripts),'findings':findings,'limitations':'Pattern scan is advisory; does not prove arbitrary control flow, lifetime or GPU correctness.'},indent=2),encoding='utf-8')
    if a.static_only:
        passed=not any(x['severity']=='risk' for x in findings)
        (out/'report.json').write_text(json.dumps({'pass':passed,'static_only':True,'static_findings':findings},indent=2),encoding='utf-8')
        print(json.dumps({'pass':passed,'static_risks':sum(x['severity']=='risk' for x in findings),'warning_candidates':sum(x['severity']=='warning_candidate' for x in findings)}),flush=True)
        raise SystemExit(0 if passed else 1)
    cmd=[str(a.engine),'--path',str(ROOT),'--log-file',str(out/'engine.log'),'--script','res://tests/integration/startup_resource_scan.gd']
    cmd+=['--rendering-method','forward_plus','--rendering-driver','d3d12','--resolution','1280x720'] if manifest['live'] else ['--headless']
    cmd+=['--','--scan-output='+out.as_posix(),'--parameter-config='+(parameters/'startup.json').as_posix()]
    (out/'command.json').write_text(json.dumps({'command':cmd,'environment_overrides':{k:env[k] for k in ['TEMP','TMP','APPDATA','LOCALAPPDATA','XDG_CACHE_HOME']}},indent=2),encoding='utf-8')
    timed_out=False
    with (out/'run.log').open('w',encoding='utf-8') as log:
        try:result=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=600);exit_code=result.returncode
        except subprocess.TimeoutExpired:timed_out=True;exit_code=None
    log=(out/'run.log').read_text(encoding='utf-8',errors='replace');issues=[];context='engine_startup'
    for line in log.splitlines():
        if line.startswith(('SCAN_BEGIN ','LIVE_BEGIN ')):context=line
        if line.startswith(('ERROR:','SCRIPT ERROR:','WARNING:','CrashHandlerException:')):issues.append({'context':context,'message':line})
    runtime=json.loads((out/'runtime.json').read_text(encoding='utf-8')) if (out/'runtime.json').is_file() else None
    drift=[rel for rel,want in before.items() if not (ROOT/rel).is_file() or hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()!=want]
    failed_checks=[] if runtime is None else [x for x in runtime['checks'] if not x.get('loaded',True) or not x.get('instances_valid',True) or (x.get('live') and (not x['ready'] or not x['advanced'] or x['error']))]
    runtime_pass=not timed_out and exit_code==0 and runtime is not None and not failed_checks and not drift and not any(x['message'].startswith(('ERROR:','SCRIPT ERROR:','CrashHandlerException:')) for x in issues)
    review_required=any(x['severity']=='risk' for x in findings)
    passed=runtime_pass and not review_required
    report={'pass':passed,'runtime_pass':runtime_pass,'review_required':review_required,'timed_out':timed_out,'exit_code':exit_code,'runtime':runtime,'source_drift':drift,'failed_checks':failed_checks,'engine_messages':issues,'static_findings':findings,'scope':'Resource load + two detached instances of every scenes/ entry; optional two live boot/advance/shutdown cycles of each formal entry. No performance or exhaustive gameplay claim.'}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'pass':passed,'exit_code':exit_code,'resources':len(resources),'scenes':len(manifest['scenes']),'scripts':len(scripts),'runtime_messages':len(issues),'static_risks':sum(x['severity']=='risk' for x in findings),'warning_candidates':sum(x['severity']=='warning_candidate' for x in findings)},ensure_ascii=False),flush=True)
    raise SystemExit(0 if passed else 1)
if __name__=='__main__':main()
