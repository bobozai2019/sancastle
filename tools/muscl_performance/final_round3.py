"""Run the frozen cumulative round-three gates serially in fresh processes."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from baseline import run,configure
from context import ROOT,add_arguments,resolve

p=argparse.ArgumentParser(description=__doc__);add_arguments(p)
p.add_argument('--a',type=Path,required=True);p.add_argument('--b',type=Path,required=True)
p.add_argument('--prefix',required=True);p.add_argument('--phase',choices=('numerical','performance','lifecycle'),required=True)
p.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
a=p.parse_args();configure(a);task,temp=resolve(a);e=task/'验收';context=['--task-root',str(task),'--temp-root',str(temp)]
def command(script,arguments):subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance'/script),*arguments],check=True)
def compare(prefix):command('compare_variant_states.py',['--a',str(e/(prefix+'_a')),'--b',str(e/(prefix+'_b')),'--output',str(e/(prefix+'_comparison.json'))])
def abba(prefix,mode,case=None):
    command('run_abba.py',[*context,'--a',str(a.a),'--b',str(a.b),'--prefix',prefix,'--mode',mode,'--telemetry']+(['--case',case] if case else []))
    command('compare_abba.py',[*context,'--prefix',prefix,'--mode',mode])

if a.phase=='numerical':
    for mode in ('variant','first-order','formal-states','material-inputs'):
        prefix=a.prefix+'_'+mode
        for name,source in [('a',a.a),('b',a.b)]:run(a.engine,prefix+'_'+name,mode,source.resolve())
        compare(prefix)
elif a.phase=='performance':
    abba(a.prefix,'cost');abba(a.prefix,'scene')
    cost=json.loads((e/(a.prefix+'_cost_comparison.json')).read_text(encoding='utf-8'))
    scene=json.loads((e/(a.prefix+'_scene_comparison.json')).read_text(encoding='utf-8'))
    metrics=cost['metrics']
    def improves(row):return row['mean_gain']>=row['required_gain'] and all(g>0 for g in row['paired_gains'])
    def regresses(row,floor):return all(g<0 for g in row['paired_gains']) and -row['mean_gain']>max(floor,row['a_relative_noise'])
    channels={key:improves(metrics[key]) for key in ('gpu_ms_per_sim_s','cpu_record_us')}
    regressions={key:regresses(metrics[key],0.02) for key in channels}
    normal={key:regresses(row,0.0) for key,row in scene['metrics'].items()}
    progression={name:[r for r in data['progress'] if r['ratio_change'] < -r['endpoint_bound']] for name,data in [('cost',cost),('scene',scene)]}
    provisional=cost['valid_identities'] and scene['valid_identities'] and any(channels.values()) and not any(regressions.values()) and not any(normal.values()) and not any(progression.values())
    result={'primary_pass':provisional,'channels_meet_gain_gate':channels,'confirmed_cost_regression':regressions,'confirmed_normal_window_regression':normal,'progress_outside_endpoint_bounds':progression,'note':'No sum of individual gains; normal-window metrics are separate from cost FPS. Original comparison files retain both paired directions and noise.'}
    (e/(a.prefix+'_performance_gate.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True)
    if not provisional:raise SystemExit(2)
    workloads={}
    for case in ('wave','shovel'):
        prefix=a.prefix+'_'+case;abba(prefix,'input-cost',case)
        data=json.loads((e/(prefix+'_input-cost_comparison.json')).read_text(encoding='utf-8'))
        workloads[case]={'valid':data['valid_identities'],'regressions':{k:regresses(data['metrics'][k],0.02) for k in ('gpu_ms_per_sim_s','cpu_record_us')},'progress_outside_endpoint_bounds':[r for r in data['progress'] if r['ratio_change'] < -r['endpoint_bound']]}
    result['workloads']=workloads
    result['pass']=provisional and all(r['valid'] and not any(r['regressions'].values()) and not r['progress_outside_endpoint_bounds'] for r in workloads.values())
    (e/(a.prefix+'_performance_gate.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    raise SystemExit(not result['pass'])
else:
    run(a.engine,a.prefix+'_main_inputs','material-inputs',a.b.resolve(),['--scene=res://scenes/main.tscn'])
    run(a.engine,a.prefix+'_main_live','main-live',a.b.resolve())
    run(a.engine,a.prefix+'_continuous','continuous',a.b.resolve())
    for case in ('ordinary','molded'):
        command('restart_readers.py',[*context,'--source-root',str(a.b),'--prefix',a.prefix+'_cold_'+case,'--case',case])
