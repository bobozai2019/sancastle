"""Strict serial coupling fixture; freeze the analysis tools before launch."""
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import time
from run_gpu import COUPLING_CASES


def run_suite(fixture_path,solver,runtime,output):
    fixture_path=Path(fixture_path).resolve();runtime=Path(runtime).resolve();output=Path(output).resolve()
    fixture=json.loads(fixture_path.read_text(encoding='utf-8'))
    if not isinstance(fixture,dict) or set(fixture)!={'schema','suite','solver_id','grid_size','cell_size_m','cases'}:raise ValueError('invalid coupling fixture keys')
    if type(fixture['schema']) is not int or fixture['schema']!=1 or fixture['suite']!='coupling' or fixture['solver_id']!=solver or solver not in ('rusanov_first_order_v1','muscl_mc_ssprk2_v1') or type(fixture['grid_size']) is not int or fixture['grid_size']!=256 or fixture['cell_size_m']!=.125:raise ValueError('unsupported coupling fixture')
    if not isinstance(fixture['cases'],list) or not 1<=len(fixture['cases'])<=32:raise ValueError('invalid cases')
    names=set()
    for case in fixture['cases']:
        if not isinstance(case,dict) or set(case)!={'id','case_id','duration_s','tick_dt_s'}:raise ValueError('invalid case keys')
        if not isinstance(case['id'],str) or not case['id'].isascii() or not case['id'].replace('_','').isalnum() or case['id'] in names or case['case_id'] not in COUPLING_CASES:raise ValueError('invalid case identity')
        names.add(case['id'])
        for key in ('duration_s','tick_dt_s'):
            if type(case[key]) not in (int,float) or not math.isfinite(case[key]):raise ValueError('nonfinite input')
        if not 0<case['duration_s']<=6 or not 0<case['tick_dt_s']<=1/30+1e-9:raise ValueError('case range')
        if solver!='muscl_mc_ssprk2_v1' and (case['case_id'].endswith('_off') or case['case_id']=='reversal'):raise ValueError('stage-only fixture')
    if not (runtime/'project.godot').is_file():raise ValueError('missing runtime')
    output.mkdir(parents=True,exist_ok=False);tools=Path(__file__).parent
    source_names=['coupling_suite.py','run_gpu.py','analyze_coupling.py','coupled_reference.py','reference.py','coupling_gpu_probe.gd','gpu_probe.gd']
    hashes={}
    for name in source_names:
        raw=(tools/name).read_bytes();hashes[name]=hashlib.sha256(raw).hexdigest();(output/name).write_bytes(raw)
    (output/'fixture.json').write_bytes(fixture_path.read_bytes());rows=[];started=time.time()
    for case in fixture['cases']:
        directory=output/case['id'];row={'id':case['id'],'outcome':'running'};rows.append(row)
        (output/'status.json').write_text(json.dumps({'rows':rows,'active_case':case['id']},indent=2),encoding='utf-8')
        command=[sys.executable,str(output/'run_gpu.py'),'--project-root',str(runtime),'--output',str(directory),'--solver',solver,'--suite','coupling','--case',case['case_id'],'--duration',str(case['duration_s']),'--tick-dt',str(case['tick_dt_s'])]
        row['command']=command;print('COUPLING_START',case['id'],flush=True)
        with (output/(case['id']+'_launcher.txt')).open('w',encoding='utf-8') as log:child=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=660)
        row['exit_code']=child.returncode
        if child.returncode:row['outcome']='fail';break
        with (output/(case['id']+'_analysis.txt')).open('w',encoding='utf-8') as log:measured=subprocess.run([sys.executable,str(output/'analyze_coupling.py'),str(directory),'--source-root',str(runtime)],stdout=log,stderr=subprocess.STDOUT,timeout=600)
        row['analysis_exit_code']=measured.returncode;row['analysis']=str(directory/'analysis.json');row['outcome']='pass' if measured.returncode==0 else 'fail'
        print('COUPLING_END',case['id'],row['outcome'],flush=True)
        if measured.returncode:break
    drift=[name for name,h in hashes.items() if hashlib.sha256((output/name).read_bytes()).hexdigest()!=h]
    result={'schema':1,'suite':'coupling','solver_id':solver,'outcome':'pass' if len(rows)==len(fixture['cases']) and all(r['outcome']=='pass' for r in rows) and not drift else 'fail',
            'fixture_sha256':hashlib.sha256((output/'fixture.json').read_bytes()).hexdigest(),'rows':rows,'source_hashes':hashes,'source_drift':drift,'elapsed_wall_s':time.time()-started,'scope':'Short actual GPU numeric/material/support suite; no performance measurement'}
    (output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('COUPLING_SUITE',result['outcome'],len(rows),'/',len(fixture['cases']),flush=True)
    return result['outcome']=='pass'
