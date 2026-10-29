"""Explicit entry point for this round's additional developer probes."""
import argparse
import json
from pathlib import Path
import subprocess
from baseline import configure, run
from context import add_arguments

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);add_arguments(p)
    p.add_argument('mode',choices=('efficiency','efficiency-exact','efficiency-diagnostic'))
    p.add_argument('--run-id',required=True);p.add_argument('--source-root',type=Path,required=True)
    p.add_argument('--scene',default='res://scenes/main.tscn');p.add_argument('--duration',type=float,default=40)
    p.add_argument('--telemetry',action='store_true');p.add_argument('--backlog',action='store_true')
    p.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
    a=p.parse_args();configure(a)
    # The editor may stay open. Any other script-driven Godot process makes a
    # new GPU run inadmissible, regardless of another task's stale lock file.
    command="Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^godot.*\\.exe$' } | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
    raw=subprocess.check_output(['powershell','-NoProfile','-Command',command],text=True,encoding='utf-8',errors='replace').strip()
    processes=json.loads(raw) if raw else []
    if isinstance(processes,dict):processes=[processes]
    conflicts=[r for r in processes if '--script' in (r.get('CommandLine') or '')]
    if conflicts:raise SystemExit('Other Godot script process is live; no GPU run started: '+json.dumps(conflicts))
    extra=['--scene='+a.scene,'--duration='+str(a.duration)]
    if a.backlog:extra.append('--backlog')
    run(a.engine,a.run_id,a.mode,a.source_root.resolve(),extra,a.telemetry)
