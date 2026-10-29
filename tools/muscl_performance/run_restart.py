"""Cold restart within a fixed candidate, retaining checkpoints and full evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from baseline import run,ROOT,configure
from context import add_arguments,resolve

parser=argparse.ArgumentParser(description=__doc__)
add_arguments(parser)
parser.add_argument('--prefix',required=True)
parser.add_argument('--source-root',type=Path,required=True)
parser.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
args=parser.parse_args();configure(args);TASK,TEMP=resolve(args);source=args.source_root.resolve();evidence=TASK/'验收'
seed_id=args.prefix+'_restart_seed';resume_id=args.prefix+'_restart_resume'
run(args.engine,seed_id,'restart',source,['--mode=seed'])
seed=evidence/seed_id/'data/seed.sandue'
run(args.engine,resume_id,'restart',source,['--mode=resume','--input='+seed.as_posix()])
for name in [seed_id,resume_id]:
    r=json.loads((evidence/name/'data/result.json').read_text(encoding='utf-8'))
    assert r['outcome']=='pass' and not r['source_drift'],name
target=TEMP/(args.prefix+'_restart_comparison')
target.mkdir(parents=True,exist_ok=False)
for name,run_id in [('seed',seed_id),('resume',resume_id)]:
    shutil.copytree(evidence/run_id/'data',target/name/'data')
command=[str(args.engine),'--headless','--path',str(source),'--script','res://tools/wave_propagation/compare_native_restart.gd','--',target.as_posix()]
with (target/'comparison.log').open('w',encoding='utf-8') as log:
    result=subprocess.run(command,cwd=source,stdout=log,stderr=subprocess.STDOUT,timeout=60)
(target/'command.txt').write_text(subprocess.list2cmdline(command),encoding='utf-8')
comparison=json.loads((target/'comparison.json').read_text(encoding='utf-8'))
assert result.returncode==0 and comparison['outcome']=='pass',comparison
assert not any(line.startswith(('ERROR:','SCRIPT ERROR:')) for line in (target/'comparison.log').read_text(encoding='utf-8').splitlines())
destination=evidence/(args.prefix+'_restart_comparison')
shutil.copytree(target,destination)
(destination/'identity.json').write_text(json.dumps({p.relative_to(destination).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in destination.rglob('*') if p.is_file()},indent=2),encoding='utf-8')
print('COLD_RESTART_EXACT PASS',flush=True)
