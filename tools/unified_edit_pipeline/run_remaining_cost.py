"""Retain six valid dig samples; finish only the unaffected missing cost groups."""
import json
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
def main():
    steps=[('g8_cost_detailed_remaining02',['--modes','detailed','--cases','fill','wall','shovel']),('g8_cost_coarse02',['--modes','coarse'])]
    for name,arguments in steps:
        command=[sys.executable,str(ROOT/'tools/unified_edit_pipeline/run_final_cost.py'),'--output',str(ROOT/'test_output/unified_edit_pipeline'/name),'--reference','D:/godot/test_runs/uep_g8_reference02',*arguments]
        print('COST_GROUP_START',name,flush=True)
        with (ROOT/'test_output/unified_edit_pipeline'/(name+'_runner.txt')).open('w',encoding='utf-8') as stream:done=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
        assert done.returncode==0,name+' failed; original evidence retained'
        print('COST_GROUP_PASS',name,flush=True)
if __name__=='__main__':main()
