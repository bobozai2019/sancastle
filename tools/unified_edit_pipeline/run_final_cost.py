"""Alternating old/current visible process pairs with exact input/source evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from run_presentation import ENGINE,FATAL
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inventory():
    value=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name like 'godot%'\" | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"],text=True,encoding='utf-8-sig').strip()
    data=json.loads(value) if value else []
    return data if isinstance(data,list) else [data]
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--repeats',type=int,default=3);p.add_argument('--cases',nargs='+',choices=['dig','fill','wall','shovel'],default=['dig','fill','wall','shovel']);p.add_argument('--modes',nargs='+',choices=['coarse','detailed'],default=['detailed','coarse']);args=p.parse_args()
    assert args.repeats>=1
    before=inventory();assert all('--editor' in x.get('CommandLine','') for x in before),'Another game/probe is active; preserve it and wait'
    folder=args.output.resolve();folder.mkdir(parents=True,exist_ok=False)
    reference=args.reference.resolve();index=json.loads((reference/'reference-index.json').read_text('utf-8'))
    for name,item in index['files'].items():
        if not name.startswith('.godot/'):assert sha(reference/name)==item['sha256'],name
    frozen=json.loads((ROOT/'test_output/unified_edit_pipeline/g8_formal_frozen01/frozen.json').read_text('utf-8'))['sources']
    for name in ['tools/unified_edit_pipeline/run_final_cost.py','tools/unified_edit_pipeline/current_cost_probe.gd','tests/integration/unified_edit_cost_executor_proxy.gd']:frozen[name]=sha(ROOT/name)
    result={'pass':False,'runs':[],'current_sources':frozen,'reference_index_sha256':sha(reference/'reference-index.json'),'engine_sha256':sha(ENGINE),'processes_before':before,'scope':'Three alternating old/current pairs per tool/mode by default; independent audit must judge identical actual 11-field inputs, camera, focus, window and complete load before any performance claim.'}
    try:
        for mode in args.modes:
            for tool in args.cases:
                for repeat in range(args.repeats):
                    for family in (['old','current'] if repeat%2==0 else ['current','old']):
                        name=f'{mode}_{tool}_{repeat}_{family}';target=folder/name;target.mkdir()
                        project=reference if family=='old' else ROOT
                        script='res://tools/unified_edit_pipeline/reference_cost_probe.gd' if family=='old' else 'res://tools/unified_edit_pipeline/current_cost_probe.gd'
                        command=[str(ENGINE),'--path',str(project),'--rendering-driver','d3d12','--script',script,'--log-file',str(target/'probe.log'),'--','--output='+str(target/'probe.json'),'--case='+tool]
                        if mode=='detailed':command.append('--sampling')
                        with (target/'stdout.txt').open('w',encoding='utf-8') as stream:done=subprocess.run(command,cwd=project,stdout=stream,stderr=subprocess.STDOUT,timeout=300)
                        evidence=target/'probe.json';data=json.loads(evidence.read_text('utf-8')) if evidence.exists() else {}
                        clean=all(not FATAL.search((target/log).read_text('utf-8-sig',errors='replace')) for log in ['stdout.txt','probe.log'])
                        passed=done.returncode==0 and clean and data.get('pass') is True
                        result['runs'].append({'name':name,'mode':mode,'tool':tool,'repeat':repeat,'family':family,'command':command,'exit_code':done.returncode,'clean_logs':clean,'pass':passed,'evidence':str(evidence),'evidence_sha256':sha(evidence) if evidence.exists() else None})
                        assert passed,name+' failed; preserve evidence'
                        assert all(sha(ROOT/name)==digest for name,digest in frozen.items()),'current source drift'
                        for name,item in index['files'].items():
                            if not name.startswith('.godot/'):assert sha(reference/name)==item['sha256'],'reference source drift: '+name
                        print('COST',result['runs'][-1]['name'],'PASS',flush=True)
        result['pass']=True
    finally:
        result['processes_after']=inventory();(folder/'report.json').write_text(json.dumps(result,indent=2),'utf-8')
if __name__=='__main__':main()
