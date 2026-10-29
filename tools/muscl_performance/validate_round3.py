"""Serial candidate gates: actual bytes, fault snapshots, lifecycle, then cost."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from baseline import run, configure
from context import ROOT, add_arguments, resolve

p=argparse.ArgumentParser(description=__doc__);add_arguments(p)
p.add_argument('--source-root',type=Path,required=True)
p.add_argument('--base',type=Path,required=True)
p.add_argument('--previous-exact',required=True)
p.add_argument('--reference-fault-prefix',required=True)
p.add_argument('--prefix',required=True)
p.add_argument('--cold',action='store_true')
p.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
a=p.parse_args();configure(a);task,temp=resolve(a);e=task/'验收';source=a.source_root.resolve()
context=['--task-root',str(task),'--temp-root',str(temp)]
run(a.engine,a.prefix+'_exact','variant',source)
subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/compare_variant_states.py'),'--a',str(e/a.previous_exact),'--b',str(e/(a.prefix+'_exact')),'--output',str(e/(a.prefix+'_exact_comparison.json'))],check=True)
faults={}
def observations(name):
    r=json.loads((e/name/'result.json').read_text(encoding='utf-8'))
    assert r['outcome']=='pass',name
    return {'fault':r['fault'],'snapshots':[{k:v for k,v in row.items() if k!='fields'}|{'fields':{k:{'bytes':v['bytes'],'sha256':v['sha256']} for k,v in row['fields'].items()}} for row in r['snapshots']]}
for case in ('negative','nonfinite'):
    name=a.prefix+'_'+case
    run(a.engine,name,'special',source,['--case='+case])
    faults[case]={'equal':observations(name)==observations(a.reference_fault_prefix+'_'+case+'_v1')}
(e/(a.prefix+'_fault_comparison.json')).write_text(json.dumps(faults,indent=2),encoding='utf-8')
assert all(v['equal'] for v in faults.values()),faults
run(a.engine,a.prefix+'_init_compile','initialization',source,['--case=init_compile'])
if a.cold:
    for case in ('ordinary','molded'):
        subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/restart_readers.py'),*context,'--source-root',str(source),'--prefix',a.prefix+'_cold_'+case,'--case',case],check=True)
subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/run_abba.py'),*context,'--a',str(a.base),'--b',str(source),'--prefix',a.prefix,'--mode','cost','--telemetry'],check=True)
subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/compare_abba.py'),*context,'--prefix',a.prefix,'--mode','cost'],check=True)
