"""Serial validation of current-layout material-finish integration."""
from pathlib import Path
import sys,json,subprocess
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/muscl_performance'))
from baseline import run,configure
from argparse import Namespace
task=Path(__file__).resolve().parent
temp=ROOT/'test_output/muscl_material_finish_20261025'
configure(Namespace(task_root=task,temp_root=temp,baseline_id=None))
e=task/'验收'; engine=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
a=temp/'projects/a0';b=temp/'projects/combined'
phase=sys.argv[1]; records=[]
def save(): (e/(phase+'_validation.json')).write_text(json.dumps(records,indent=2),encoding='utf-8')
def pair(label,mode,extra=()):
    for side,source in [('a',a),('b',b)]:
        run(engine,label+'_'+side,mode,source,extra)
    output=e/(label+'_comparison.json')
    subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/compare_variant_states.py'),'--a',str(e/(label+'_a')),'--b',str(e/(label+'_b')),'--output',str(output)],check=True)
    records.append({'label':label,'pass':True,'comparison':str(output)});save()
try:
    if phase=='core':
        pair('variant_v1','variant');pair('first_order_v1','first-order')
        for case in ['negative','nonfinite']:
            values=[]
            for side,source in [('a',a),('b',b)]:
                name=case+'_v1_'+side;run(engine,name,'special',source,['--case='+case])
                d=json.loads((e/name/'result.json').read_text(encoding='utf-8'));assert d['outcome']=='pass'
                values.append({'fault':d['fault'],'snapshots':[{k:v for k,v in x.items() if k!='fields'}|{'fields':{k:{'bytes':v['bytes'],'sha256':v['sha256']} for k,v in x['fields'].items()}} for x in d['snapshots']]})
            assert values[0]==values[1],case
            records.append({'label':case,'pass':True});save()
        run(engine,'init_compile_v1','initialization',b,['--case=init_compile'])
        records.append({'label':'init_compile','pass':True});save()
        for side,source in [('a',a),('b',b)]:run(engine,'footprint_v1_'+side,'footprint',source,['--case=coupled'])
        for name,path in [('main','res://scenes/main.tscn'),('geometry','res://scenes/playable/test1_geometry.tscn')]:
            pair(name+'_inputs_v1','material-inputs',['--scene='+path])
    elif phase=='restore':
        for case in ['ordinary','molded']:
            subprocess.run([sys.executable,str(ROOT/'tools/muscl_performance/restart_readers.py'),'--task-root',str(task),'--temp-root',str(temp),'--source-root',str(b),'--prefix','cold_'+case+'_v1','--case',case],check=True)
            records.append({'label':case,'pass':True});save()
    elif phase=='live':
        run(engine,'main_live_v1','main-live',ROOT)
        run(engine,'continuous_v1','continuous',ROOT,['--duration=120'])
        records.append({'label':'actual_root_main_and_continuous','pass':True});save()
except BaseException as ex:
    records.append({'pass':False,'error':repr(ex)});save();raise
print('VALIDATION COMPLETE',phase,flush=True)
