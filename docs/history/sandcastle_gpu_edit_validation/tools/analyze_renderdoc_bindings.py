"""Validate owned frame59 native exports and compare actual material constants."""
import ast
import hashlib
import json
from pathlib import Path
import numpy as np

root=Path('D:/godot/project/sandcastle/task/sandcastle_gpu_edit_validation/evidence/20261011_091015_renderdoc')
report=json.loads((root/'binding_probe_pid_16968.json').read_text())
assert report['pass']
source=Path(report['capture'])
assert hashlib.sha256(source.read_bytes()).hexdigest()==report['capture_sha256']
host=json.loads((root/'beach_edit_process_probe.json').read_text())
pushes=next(row['pushes'] for row in host['rows'] if row['case']=='actual_material_push_bytes_match')
host_by_stage={stage:{bytes(ast.literal_eval(p['bytes'])).hex() for p in pushes if p['stage']==stage} for stage in ('step','slope')}
rows=[]
exports={}
for row in report['rows']:
    names=row.get('readwrite',[])
    stage=('sediment' if 'sediment_out' in names else 'material_step' if 'compaction_out' in names else 'material_slope' if 'dirty_max_um' in names and 'rock_state' in names else 'material_commit' if 'compaction_dst' in names else 'other')
    item={'event':row['event'],'stage':stage,'shader':row['shader'],'constants':[],'exports':[]}
    for block in row.get('constants',[]):
        value={'buffer':block['resourceId'],'raw_hex':block.get('buffer_hex'),'byte_size':block['byte_size'],'binding_error':block.get('binding_error')}
        if stage in ('material_step','material_slope'):
            value['matches_recorded_host_stage_bytes']=value['raw_hex'] in host_by_stage[stage.removeprefix('material_')]
            assert value['matches_recorded_host_stage_bytes']
        item['constants'].append(value)
    for bound in row.get('resource_bindings',[]):
        if 'export' not in bound: continue
        meta=bound['export']
        data=(root/meta['path']).read_bytes()
        assert len(data)==meta['size']==256*256*4
        assert hashlib.sha256(data).hexdigest()==meta['sha256']
        assert bound['format']=='R32_FLOAT',bound
        values=np.frombuffer(data,dtype='<f4')
        assert np.isfinite(values).all() and values.min()>=0
        name=names[bound['reflection_index']]
        exports[(row['event'],name)]=data
        item['exports'].append({'name':name,'resource':bound['resource'],'path':meta['path'],'sha256':meta['sha256'],'size':len(data),'view_format':bound['format'],'storage_format':meta['format'],'minimum':float(values.min()),'maximum':float(values.max())})
    rows.append(item)
pairs=[((152,'sand_out'),(182,'sand_in')),((182,'sand_in'),(187,'sand_in')),((187,'sand_out'),(192,'sand_src')),((192,'sand_src'),(192,'sand_dst')),((192,'sand_dst'),(215,'sand_in')),((215,'sand_out'),(221,'sand_in')),((221,'sand_in'),(226,'sand_in')),((226,'sand_out'),(231,'sand_src')),((231,'sand_src'),(231,'sand_dst'))]
checks=[]
for left,right in pairs:
    equal=exports[left]==exports[right]
    checks.append({'left':list(left),'right':list(right),'byte_equal':equal})
    assert equal,(left,right)
result={'pass':True,'scope':'Own successful writer capture only. Stage labels inferred from unique reflected resource sets and matching source dispatches; no cold failure-pair claim.','source_sha256':report['capture_sha256'],'report':'binding_probe_pid_16968.json','exports':len(exports),'rows':rows,'transitions':checks,'host_match_scope':'Membership in actual host stage byte set; not an exact revision or tick mapping.'}
(root/'binding_analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'pass':True,'exports':len(exports),'transitions':len(checks),'material_constant_matches':sum('matches_recorded_host_stage_bytes' in c for r in rows for c in r['constants'])}))
