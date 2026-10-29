"""Serial, explicit GPU water fixture runner; each case retains its own process."""
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import time
from run_gpu import CASES


def run_suite(fixture_path, solver, runtime, output):
    fixture_path=Path(fixture_path).resolve();runtime=Path(runtime).resolve();output=Path(output).resolve()
    fixture=json.loads(fixture_path.read_text(encoding='utf-8'))
    if not isinstance(fixture,dict) or set(fixture)!={'schema','suite','solver_id','grid_size','cell_size_m','cases'}:
        raise ValueError('invalid water fixture keys')
    if type(fixture['schema']) is not int or fixture['schema']!=1 or fixture['suite']!='water' or fixture['solver_id']!=solver or solver not in ('rusanov_first_order_v1','muscl_mc_ssprk2_v1') or type(fixture['grid_size']) is not int or fixture['grid_size']!=256 or fixture['cell_size_m']!=.125:
        raise ValueError('unsupported water fixture')
    if not isinstance(fixture['cases'],list) or not 1<=len(fixture['cases'])<=64:raise ValueError('invalid water cases')
    names=set()
    for case in fixture['cases']:
        if not isinstance(case,dict) or set(case)!={'id','case_id','duration_s','depth_m','amplitude_m','tick_dt_s','cpu_replay'}:raise ValueError('invalid water case keys')
        if not isinstance(case['id'],str) or not case['id'].replace('_','').isalnum() or not case['id'].isascii() or case['id'] in names or case['case_id'] not in CASES or type(case['cpu_replay']) is not bool:raise ValueError('invalid case identity')
        names.add(case['id'])
        for key in ('duration_s','depth_m','amplitude_m','tick_dt_s'):
            if type(case[key]) not in (int,float) or not math.isfinite(case[key]):raise ValueError('nonfinite case input')
        if not 0<case['duration_s']<=6 or not .005<=case['depth_m']<=1 or not 0<case['amplitude_m']<=.01 or not 0<case['tick_dt_s']<=1/30+1e-9:raise ValueError('case range')
    if not (runtime/'project.godot').is_file():raise ValueError('missing runtime')
    output.mkdir(parents=True,exist_ok=False)
    tools=Path(__file__).parent
    sources=[Path(__file__),tools/'run_gpu.py',tools/'gpu_probe.gd',tools/'analyze_gpu.py',tools/'reference.py']
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    for p in sources:(output/p.name).write_bytes(p.read_bytes())
    (output/'fixture.json').write_bytes(fixture_path.read_bytes())
    rows=[];started=time.time()
    for case in fixture['cases']:
        directory=output/case['id']
        command=[sys.executable,str(tools/'run_gpu.py'),'--project-root',str(runtime),'--output',str(directory),'--solver',solver,'--case',case['case_id'],
                 '--duration',str(case['duration_s']),'--depth',str(case['depth_m']),'--amplitude',str(case['amplitude_m']),'--tick-dt',str(case['tick_dt_s'])]
        row={'id':case['id'],'command':command,'outcome':'running'}
        rows.append(row)
        (output/'status.json').write_text(json.dumps({'rows':rows,'active_case':case['id']},indent=2),encoding='utf-8')
        print('GPU_CASE_START',case['id'],flush=True)
        with (output/(case['id']+'_launcher.txt')).open('w',encoding='utf-8') as log:
            child=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=660)
        row['exit_code']=child.returncode
        if child.returncode:
            row['outcome']='fail';break
        analysis=[sys.executable,str(tools/'analyze_gpu.py'),str(directory),'--source-root',str(runtime)]
        if case['cpu_replay']:analysis.append('--cpu')
        with (output/(case['id']+'_analysis.txt')).open('w',encoding='utf-8') as log:
            measured=subprocess.run(analysis,stdout=log,stderr=subprocess.STDOUT,timeout=600)
        row['analysis_exit_code']=measured.returncode
        row['outcome']='pass' if measured.returncode==0 else 'fail'
        row['analysis']=str(directory/('analysis_cpu.json' if case['cpu_replay'] else 'analysis.json'))
        print('GPU_CASE_END',case['id'],row['outcome'],flush=True)
        if measured.returncode:break
    drift=[p for p,h in hashes.items() if hashlib.sha256(Path(p).read_bytes()).hexdigest()!=h]
    result={'suite':'water','outcome':'pass' if len(rows)==len(fixture['cases']) and all(r['outcome']=='pass' for r in rows) and not drift else 'fail',
            'solver_id':solver,'fixture_sha256':hashlib.sha256(fixture_path.read_bytes()).hexdigest(),'rows':rows,'source_hashes':hashes,'source_drift':drift,
            'elapsed_wall_s':time.time()-started,'scope':'Serial GPU numeric water suite; no production erosion, gameplay or performance acceptance'}
    (output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('WATER_SUITE',result['outcome'],len(rows),'/',len(fixture['cases']),flush=True)
    return result['outcome']=='pass'
