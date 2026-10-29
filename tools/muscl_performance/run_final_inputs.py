"""Serial final wave/tool costs with fixed completed-tick public inputs."""
from pathlib import Path
from baseline import ROOT,run

engine=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
projects=ROOT/'test_output/muscl_performance_round2/projects'
for case in ('wave','shovel'):
    for name,project in [('a1','diagnostic_final'),('b1','t04_retry_v1'),('b2','t04_retry_v1'),('a2','diagnostic_final')]:
        run(engine,f't07_{case}_cost_{name}','input-cost',projects/project,['--case='+case],telemetry=True)
