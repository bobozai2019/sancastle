"""Serial current-workspace formal inputs, visible endurance, and cold restart."""
from pathlib import Path
import argparse
import subprocess
import sys
from baseline import ROOT,run

engine=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix',required=True,help='Fresh evidence prefix; existing evidence is never overwritten')
args=parser.parse_args()
run(engine,args.prefix+'_main_inputs','formal-inputs',ROOT,['--scene=res://scenes/main.tscn'])
run(engine,args.prefix+'_continuous','continuous',ROOT)
subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/run_restart.py'),'--prefix',args.prefix,'--source-root',str(ROOT)],check=True)
print('FINAL_LIFECYCLE_FINISHED',flush=True)
