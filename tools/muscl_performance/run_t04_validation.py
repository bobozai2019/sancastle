"""Serial T04 numerical, resource and failure validation before performance."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
from baseline import run,ROOT,TASK

projects=ROOT/'test_output/muscl_performance_round2/projects'
evidence=TASK/'验收'
engine=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
for project in ('diagnostic_final','t04_retry_v1'):
    for name in ('fixture_upload.gd','variant_states.gd','cache_footprint.gd','initialization_probe.gd'):
        shutil.copy2(ROOT/'tools/muscl_performance'/name,projects/project/'tools/muscl_performance'/name)
for name,project in [('a','diagnostic_final'),('b','t04_retry_v1')]:
    run(engine,'t04_states_'+name+'_v2','variant',projects/project)
subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/compare_variant_states.py'),
    '--a',str(evidence/'t04_states_a_v2'),'--b',str(evidence/'t04_states_b_v2'),
    '--output',str(evidence/'t04_state_comparison_v2.json')],check=True)
for name,project in [('a','diagnostic_final'),('b','t04_retry_v1')]:
    run(engine,'t04_footprint_'+name,'footprint',projects/project)
for case in ('negative','nonfinite'):
    run(engine,'t04_'+case+'_b','special',projects/'t04_retry_v1',['--case='+case])
for case in ('init_water','init_unknown'):
    run(engine,'t04_'+case,'initialization',projects/'t04_retry_v1',['--case='+case])
print('T04_PRE_COST_VALIDATION_FINISHED',flush=True)
