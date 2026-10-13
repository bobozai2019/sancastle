"""Serial GPU windows. Separate frozen algorithm and live full-load comparisons."""
import json
import subprocess
import sys
from pathlib import Path
from datetime import datetime

root = Path(__file__).resolve().parents[2]
base = root/'test_output/approx_gpu_edit_trial'
series = 'pairs_' + datetime.now().strftime('%Y%m%d_%H%M%S')
out = base/series
out.mkdir(exist_ok=False)
records = []
kind = sys.argv[1] if len(sys.argv)>1 else 'live'
for pair in range(3):
    selections = [['--original','--live'],['--live']] if kind=='live' else [['--exact'],[]]
    if pair%2: selections.reverse()
    for selection in selections:
        command = [sys.executable,str(root/'tools/approx_gpu_edit_trial/run_cost.py'),'--seconds=30']+selection
        before = set(base.glob('cost_*'))
        p = subprocess.run(command,capture_output=True,encoding='utf-8',errors='replace',timeout=150)
        created = [x.name for x in set(base.glob('cost_*'))-before]
        records.append({'pair':pair,'kind':kind,'args':selection,'runs':created,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
        (out/'index.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
        print('PAIR',pair,'ARGS',selection,'RUN',created,'EXIT',p.returncode,flush=True)
        if p.returncode: raise SystemExit(p.returncode)
print('SERIES',series,flush=True)
