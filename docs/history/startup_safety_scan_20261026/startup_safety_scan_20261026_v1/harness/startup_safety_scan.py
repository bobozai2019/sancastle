"""Scan startup resource hazards and exercise scene construction in Godot.

All generated output and configurable caches stay within the project.
"""
from pathlib import Path
import argparse,os,json,re,subprocess,shutil,datetime
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
    p.add_argument('--live',action='store_true',help='Also boot, advance and shut down both formal entries twice')
    a=p.parse_args();out=a.output.resolve()
    if not out.is_relative_to(ROOT) or out==ROOT:raise SystemExit('Output must be a dedicated directory inside project')
    out.mkdir(parents=True,exist_ok=False)
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
        for m in re.finditer(r'^\[(?:sub_resource|gd_resource)\b[^\n]*type="MultiMesh"[^\n]*\n([\s\S]*?)(?=^\[|\Z)',text,re.M):
            block=m[0];count=re.search(r'^instance_count\s*=\s*(\d+)',block,re.M)
            if not count or int(count[1])==0:continue
            if re.search(r'^resource_local_to_scene\s*=\s*true',block,re.M):
                findings.append({'rule':'R001','severity':'risk','file':rel,'line':text[:m.start()].count('\n')+1,'message':'Allocated MultiMesh uses generic scene-local duplication; reproduce construction before changing it.'})
            for prop in ['transform_format','use_colors','use_custom_data']:
                setting=re.search(r'^'+prop+r'\s*=',block,re.M)
                if setting and setting.start()>count.start():findings.append({'rule':'R002','severity':'risk','file':rel,'line':text[:m.start()+setting.start()].count('\n')+1,'message':prop+' serialized after nonzero instance_count'})
    scripts=sorted(ROOT.glob('scripts/**/*.gd'))
    for f in scripts:
        text=f.read_text(encoding='utf-8-sig');states={}
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
    manifest={'resources':[f'res://{f.relative_to(ROOT).as_posix()}' for f in resources],'scenes':[f'res://{f.relative_to(ROOT).as_posix()}' for f in resources if f.suffix=='.tscn'],'live':a.live}
    (out/'input.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (out/'static.json').write_text(json.dumps({'resource_files':len(resources),'scripts':len(scripts),'findings':findings,'limitations':'Pattern scan is advisory; does not prove arbitrary control flow, lifetime or GPU correctness.'},indent=2),encoding='utf-8')
    cmd=[str(a.engine),'--path',str(ROOT),'--log-file',str(out/'engine.log'),'--script','res://tests/integration/startup_resource_scan.gd']
    cmd+=['--rendering-method','forward_plus','--rendering-driver','d3d12','--resolution','1280x720'] if a.live else ['--headless']
    cmd+=['--','--scan-output='+out.as_posix(),'--parameter-config='+(parameters/'startup.json').as_posix()]
    (out/'command.json').write_text(json.dumps({'command':cmd,'environment_overrides':{k:env[k] for k in ['TEMP','TMP','APPDATA','LOCALAPPDATA','XDG_CACHE_HOME']}},indent=2),encoding='utf-8')
    with (out/'run.log').open('w',encoding='utf-8') as log:result=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=600)
    log=(out/'run.log').read_text(encoding='utf-8',errors='replace');issues=[];context='engine_startup'
    for line in log.splitlines():
        if line.startswith(('SCAN_BEGIN ','LIVE_BEGIN ')):context=line
        if line.startswith(('ERROR:','SCRIPT ERROR:','WARNING:')):issues.append({'context':context,'message':line})
    runtime=json.loads((out/'runtime.json').read_text(encoding='utf-8')) if (out/'runtime.json').is_file() else None
    report={'exit_code':result.returncode,'runtime':runtime,'engine_messages':issues,'static_findings':findings,'scope':'Resource load + two detached instances of every scenes/ entry; optional two live boot/advance/shutdown cycles of each formal entry. No performance or exhaustive gameplay claim.'}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'exit_code':result.returncode,'resources':len(resources),'scenes':len(manifest['scenes']),'scripts':len(scripts),'runtime_messages':len(issues),'static_risks':sum(x['severity']=='risk' for x in findings),'warning_candidates':sum(x['severity']=='warning_candidate' for x in findings)},ensure_ascii=False),flush=True)
    raise SystemExit(result.returncode)
if __name__=='__main__':main()
