"""Serialize A/B windows; keep contaminated attempts and wait for external game probes."""
import argparse, json, subprocess, sys, time
from pathlib import Path
from windows_telemetry import Telemetry
p=argparse.ArgumentParser();p.add_argument('--project',required=True);p.add_argument('--archive',required=True);p.add_argument('--origin',required=True);p.add_argument('--prefix',default='t04_formal');a=p.parse_args()
archive=Path(a.archive);status=archive/(a.prefix+'_status.json');monitor=Telemetry(0)
completed=[];editor_pid=3192
def write(stage,**extra):status.write_text(json.dumps({'stage':stage,'completed':completed,'updated_utc_ns':time.time_ns(),**extra},indent=2))
try:
    for pair,order in enumerate(['AB','BA','AB'],1):
        for mode in order:
            accepted=False
            for attempt in range(1,4):
                quiet=0
                while quiet<6:
                    external=[v for v in monitor.sample()['processes'] if v['pid']!=editor_pid]
                    write('waiting_external' if external else 'quiet_check',pair=pair,mode=mode,external=external,quiet_samples=quiet)
                    quiet=0 if external else quiet+1
                    time.sleep(5)
                name=f'{a.prefix}_P{pair}_{mode}_attempt{attempt}'
                write('running',pair=pair,mode=mode,name=name)
                command=[sys.executable,str(Path(__file__).with_name('run_cost.py')),'--project',a.project,'--archive',a.archive,'--name',name,'--origin',a.origin,'--policy','baseline' if mode=='A' else 'worker2','--minimum','1' if mode=='A' else '16','--seconds','300']
                with (archive/(name+'_runner.log')).open('w') as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
                folder=archive/name
                if result.returncode:write('probe_failed',name=name,exit=result.returncode);raise SystemExit(1)
                own=json.loads((folder/'live_process.json').read_text())['pid']
                external=sorted({v['pid'] for line in (folder/'telemetry.jsonl').read_text().splitlines() for v in json.loads(line)['processes'] if v['pid'] not in [own,editor_pid]})
                validity={'external_game_pids':external,'external_game_load_clear':not external,'editor_pid_preserved':editor_pid,'telemetry_interval_s':1,'limitation':'sub-second external processes can escape sampling'}
                (folder/'load_validity.json').write_text(json.dumps(validity,indent=2))
                completed.append({'pair':pair,'mode':mode,'name':name,'load_clear':not external})
                if not external:accepted=True;break
            if not accepted:write('external_load_repeated',pair=pair,mode=mode);raise SystemExit(2)
    write('all_windows_complete')
finally:monitor.close()
