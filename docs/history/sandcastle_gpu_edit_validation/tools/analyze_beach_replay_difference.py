"""Compare exported native checkpoint bytes and completed-tick sand copies."""
import hashlib
import json
from pathlib import Path
import numpy as np

base=Path('D:/godot/project/sandcastle/task/sandcastle_gpu_edit_validation/evidence')
root=base/'20261011_102953_beach_replay_original_probe'
exports=json.loads((root/'checkpoint_diff_exports.json').read_text())
a,b=exports['before'],exports['replayed']
rows=[]
for field in a['files']:
    am,bm=a['files'][field],b['files'][field]
    ad,bd=(root/am['path']).read_bytes(),(root/bm['path']).read_bytes()
    assert hashlib.sha256(ad).hexdigest()==am['sha256'] and hashlib.sha256(bd).hexdigest()==bm['sha256']
    dtype='u1' if field.endswith('obstacle') else '<f2' if field.endswith(('wetness','compaction')) else '<f4'
    av,bv=np.frombuffer(ad,dtype=dtype),np.frombuffer(bd,dtype=dtype)
    changed=np.flatnonzero(av!=bv)
    rows.append({'field':field,'byte_equal':ad==bd,'changed_components':len(changed),'max_absolute_difference':float(np.max(np.abs(av.astype('f8')-bv.astype('f8')))),'samples':[{'component':int(i),'before':float(av[i]),'replayed':float(bv[i])} for i in changed[:16]]})
result={'scope':'Default original branch FAIL; raw exports from stored checkpoints, no recomputation','metadata_equal':{key:a[key]==b[key] for key in ('tick','revision','index','foam_index','ledger','prefix')},'fields':rows}
(root/'native_difference_analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
root=base/'20261011_103811_beach_replay_original_probe'
rows=[]
for tick in range(1,20):
    paths=[root/('trace_%s_tick_%d.bin'%(label,tick)) for label in ('active','worker')]
    raw=[p.read_bytes() for p in paths]
    av,bv=[np.frombuffer(d,dtype='<f4') for d in raw]
    changed=np.flatnonzero(av!=bv)
    rows.append({'tick':tick,'byte_equal':raw[0]==raw[1],'changed_cells':len(changed),'maximum':float(np.max(np.abs(av-bv))),'sources':[{'path':p.name,'sha256':hashlib.sha256(d).hexdigest(),'size':len(d)} for p,d in zip(paths,raw)],'samples':[{'cell':int(i),'active':float(av[i]),'worker':float(bv[i])} for i in changed[:16]]})
(root/'sand_tick_difference_analysis.json').write_text(json.dumps({'scope':'GPU-copy diagnostic variant, not unobserved default first divergence','first_different_tick':next(r['tick'] for r in rows if not r['byte_equal']),'rows':rows},indent=2),encoding='utf-8')
print('Default exported differences and diagnostic first sand divergence at tick 8 indexed.')
