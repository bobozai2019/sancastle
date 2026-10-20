"""Execute the explicit prepared MUSCL lifecycle matrix, retaining failures."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import zipfile
from run_lifecycle_case import CASES


def run_suite(fixture_path,solver,runtime,output):
    fixture_path=Path(fixture_path).resolve();runtime=Path(runtime).resolve();output=Path(output).resolve()
    f=json.loads(fixture_path.read_text(encoding='utf-8'))
    if not isinstance(f,dict) or set(f)!={'schema','suite','solver_id','cases'} or type(f['schema']) is not int or f['schema']!=1 or f['suite']!='lifecycle' or f['solver_id']!=solver or solver!='muscl_mc_ssprk2_v1':raise ValueError('invalid lifecycle fixture')
    if not isinstance(f['cases'],list) or not 1<=len(f['cases'])<=48:raise ValueError('invalid cases')
    names=set()
    for row in f['cases']:
        if not isinstance(row,dict) or set(row)!={'id','kind','case_id'} or row['kind'] not in CASES or row['case_id'] not in CASES[row['kind']] or not isinstance(row['id'],str) or not row['id'].isascii() or not row['id'].replace('_','').isalnum() or row['id'] in names:raise ValueError('invalid lifecycle case')
        names.add(row['id'])
    preparation=runtime/'tools/wave_propagation/g4_generated/preparation.json'
    if not preparation.is_file():raise ValueError('prepare explicit algorithm variants first')
    output.mkdir(parents=True,exist_ok=False);tools=Path(__file__).parent
    for name in ['lifecycle_suite.py','run_lifecycle_case.py']:(output/name).write_bytes((tools/name).read_bytes())
    (output/'fixture.json').write_bytes(fixture_path.read_bytes());(output/'preparation.json').write_bytes(preparation.read_bytes());rows=[];started=time.time()
    for case in f['cases']:
        directory=output/case['id'];row={'id':case['id'],'outcome':'running'};rows.append(row)
        (output/'status.json').write_text(json.dumps({'rows':rows,'active_case':case['id']},indent=2),encoding='utf-8');print('LIFECYCLE_START',case['id'],flush=True)
        with (output/(case['id']+'_launcher.txt')).open('w',encoding='utf-8') as log:child=subprocess.run([sys.executable,str(output/'run_lifecycle_case.py'),'--runtime',str(runtime),'--output',str(directory),'--kind',case['kind'],'--case',case['case_id']],stdout=log,stderr=subprocess.STDOUT,timeout=390)
        row.update(exit_code=child.returncode,outcome='pass' if child.returncode==0 else 'fail')
        report=directory/('probe.json' if case['kind'].startswith('formal_') else 'result.json')
        if report.exists():
            data=json.loads(report.read_text(encoding='utf-8'));sources=data.get('source_hashes',data.get('observations',{}).get('sources',{}));row['report']=str(report)
            if not sources:row['outcome']='fail';row['missing_sources']=True
            else:
                drift=[]
                with zipfile.ZipFile(directory/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
                    for name,expected in sources.items():
                        raw=(runtime/name.removeprefix('res://')).read_bytes()
                        if hashlib.sha256(raw).hexdigest()!=expected:drift.append(name)
                        z.writestr(name.removeprefix('res://'),raw)
                row['source_drift']=drift
                if drift:row['outcome']='fail'
        else:row['outcome']='fail'
        print('LIFECYCLE_END',case['id'],row['outcome'],flush=True)
        if row['outcome']!='pass':break
    result={'schema':1,'suite':'lifecycle','solver_id':solver,'outcome':'pass' if len(rows)==len(f['cases']) and all(r['outcome']=='pass' for r in rows) else 'fail','rows':rows,'fixture_sha256':hashlib.sha256((output/'fixture.json').read_bytes()).hexdigest(),'elapsed_wall_s':time.time()-started,'scope':'Only the explicit fixture cases; no implicit whole-G4 acceptance or performance measurement'}
    (output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('LIFECYCLE_SUITE',result['outcome'],len(rows),'/',len(f['cases']),flush=True);return result['outcome']=='pass'
