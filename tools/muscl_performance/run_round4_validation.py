"""Serial round-four functional matrices; fresh evidence prefixes only."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from baseline import run,configure,ROOT
from context import add_arguments,resolve
from layout_contract import split,differences

p=argparse.ArgumentParser(description=__doc__);add_arguments(p)
p.add_argument('--a',type=Path,required=True);p.add_argument('--b',type=Path,required=True)
p.add_argument('--prefix',required=True);p.add_argument('--phase',choices=('core','formal'),required=True)
p.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
a=p.parse_args();configure(a);task,temp=resolve(a);e=task/'验收'
records=[];report=e/(a.prefix+'_matrix.json')
if report.exists():raise SystemExit('Fresh prefix required')


def save():
    report.write_text(json.dumps({'phase':a.phase,'records':records},indent=2),'utf-8')


def pair(label,mode,extra=()):
    ids=[]
    for variant,source in [('a',a.a),('b',a.b)]:
        name=a.prefix+'_'+label+'_'+variant
        run(a.engine,name,mode,source.resolve(),extra)
        ids.append(name);records.append({'run':name,'mode':mode,'source':str(source),'extra':list(extra),'pass':True});save()
    if mode!='special':
        output=e/(a.prefix+'_'+label+'_comparison.json')
        command=[sys.executable,'-X','utf8',str(ROOT/'tools/muscl_performance/compare_variant_states.py'),'--a',str(e/ids[0]),'--b',str(e/ids[1]),'--output',str(output)]
        subprocess.run(command,check=True)
        records.append({'comparison':str(output),'pass':True});save()
    else:
        normalized=[];layouts=[]
        for name in ids:
            directory=e/name;data=json.loads((directory/'result.json').read_text('utf-8'))
            assert data['outcome']=='pass' and not data['source_drift']
            states={};description=[];packed=[]
            for row in data['snapshots']:
                raw={}
                for field,meta in row['fields'].items():
                    payload=(directory/Path(meta['path']).name).read_bytes()
                    assert len(payload)==meta['bytes'] and hashlib.sha256(payload).hexdigest()==meta['sha256']
                    raw[field]=payload
                for field,x,z in [('momentum','momentum_x','momentum_z'),('slot_momentum_0','slot_momentum_x_0','slot_momentum_z_0'),('slot_momentum_1','slot_momentum_x_1','slot_momentum_z_1')]:
                    if field not in raw:continue
                    parts=split(raw.pop(field));packed.append(row['label']+'/'+field)
                    if x in raw:assert raw[x]==parts[0] and raw[z]==parts[1]
                    raw[x],raw[z]=parts
                states.update({row['label']+'/'+field:payload for field,payload in raw.items()})
                description.append({k:v for k,v in row.items() if k!='fields'})
            normalized.append((states,description,data['fault']));layouts.append(packed)
        delta=differences(normalized[0][0],normalized[1][0])
        result={'pass':not delta and normalized[0][1:]==normalized[1][1:],'difference_members':delta,'snapshot_metadata_and_fault_equal':normalized[0][1:]==normalized[1][1:],'packed_original_members':layouts,'scope':'Every captured byte including both authority slots; only explicit current/slot momentum representation normalized. Original RG bytes retained.'}
        output=e/(a.prefix+'_'+label+'_comparison.json');output.write_text(json.dumps(result,indent=2),'utf-8')
        assert result['pass'],result
        records.append({'comparison':str(output),'pass':True});save()


try:
    if a.phase=='core':
        pair('first_order','first-order')
        for case in ('negative','nonfinite'):pair(case,'special',['--case='+case])
        pair('dispatch','dispatch-trace')
    else:
        for scene,path in [('geometry','res://scenes/playable/test1_geometry.tscn'),('main','res://scenes/main.tscn')]:
            pair(scene,'material-inputs',['--scene='+path])
except BaseException as error:
    records.append({'failure':repr(error),'pass':False});save();raise
print('ROUND4_VALIDATION_PHASE_COMPLETE',a.phase,flush=True)
