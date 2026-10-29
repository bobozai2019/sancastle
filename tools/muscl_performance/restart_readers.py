"""One writer, three independent readers, exact native continuation checks."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
from baseline import run,configure
from context import add_arguments,resolve

p=argparse.ArgumentParser(description=__doc__);add_arguments(p)
p.add_argument('--source-root',type=Path,required=True);p.add_argument('--prefix',required=True)
p.add_argument('--case',choices=('ordinary','molded'),required=True)
p.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
a=p.parse_args();configure(a);task,temp=resolve(a);e=task/'验收';source=a.source_root.resolve()
writer=a.prefix+'_writer';run(a.engine,writer,'restart',source,['--mode=seed','--case='+a.case])
seed=e/writer/'data/seed.sandue';outcomes=[]
for i in range(3):
    reader=a.prefix+'_reader'+str(i+1)
    run(a.engine,reader,'restart',source,['--mode=resume','--input='+seed.as_posix(),'--case='+a.case])
    directory=temp/(reader+'_comparison');directory.mkdir(parents=True,exist_ok=False)
    for name,run_id in [('seed',writer),('resume',reader)]:shutil.copytree(e/run_id/'data',directory/name/'data')
    command=[str(a.engine),'--headless','--path',str(source),'--script','res://tools/wave_propagation/compare_native_restart.gd','--',directory.as_posix()]
    with (directory/'comparison.log').open('w',encoding='utf-8') as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    (directory/'command.json').write_text(json.dumps(command),encoding='utf-8')
    shutil.copytree(directory,e/directory.name)
    report=json.loads((directory/'comparison.json').read_text(encoding='utf-8'))
    errors=[line for line in (directory/'comparison.log').read_text(encoding='utf-8').splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:'))]
    outcomes.append({'reader':reader,'pass':r.returncode==0 and report['outcome']=='pass' and not errors,'errors':errors})
(e/(a.prefix+'_summary.json')).write_text(json.dumps({'pass':all(r['pass'] for r in outcomes),'case':a.case,'writer':writer,'readers':outcomes},indent=2),encoding='utf-8')
raise SystemExit(not all(r['pass'] for r in outcomes))
