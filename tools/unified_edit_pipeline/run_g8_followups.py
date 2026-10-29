"""Continue the active serial G8 run after the frozen matrix terminates."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
ROOT=Path(__file__).resolve().parents[2]
def main():
    p=argparse.ArgumentParser();p.add_argument('--matrix',type=Path,required=True);args=p.parse_args()
    matrix=args.matrix.resolve()
    while not (matrix/'matrix.json').exists():time.sleep(2)
    result=json.loads((matrix/'matrix.json').read_text('utf-8'))
    assert result['pass'],'Final matrix failed; no dependent GPU probe started'
    tasks=[('endurance',[sys.executable,str(ROOT/'tools/unified_edit_pipeline/run_final_endurance.py'),'--output',str(ROOT/'test_output/unified_edit_pipeline/g8_endurance01')]),
           ('cost_pilot',[sys.executable,str(ROOT/'tools/unified_edit_pipeline/run_final_cost.py'),'--output',str(ROOT/'test_output/unified_edit_pipeline/g8_cost_pilot01'),'--reference','D:/godot/test_runs/uep_g8_reference01','--repeats','1','--cases','wall','--modes','detailed','coarse'])]
    records=[]
    try:
        for name,command in tasks:
            print('FOLLOWUP_START',name,flush=True)
            with (matrix/(name+'_runner.txt')).open('w',encoding='utf-8') as stream:done=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
            records.append({'name':name,'command':command,'exit_code':done.returncode})
            assert done.returncode==0,name+' failed; original evidence retained'
            print('FOLLOWUP_PASS',name,flush=True)
    finally:(matrix/'followups.json').write_text(json.dumps({'pass':len(records)==2 and all(r['exit_code']==0 for r in records),'steps':records},indent=2),'utf-8')
if __name__=='__main__':main()
