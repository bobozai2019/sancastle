"""Index complete native trace comparisons without relaxing bit equality."""
import hashlib
import json
from pathlib import Path
import numpy as np

base=Path('D:/godot/project/sandcastle/task/sandcastle_gpu_edit_validation/evidence')
for name in ('20261011_104256_beach_replay_original_probe','20261011_104524_beach_replay_original_probe'):
    root=base/name
    rows=[]
    for path in sorted(root.glob('trace_active_tick_*_*.bin')):
        peer=root/path.name.replace('active','worker')
        ad,bd=path.read_bytes(),peer.read_bytes()
        dtype='u1' if path.stem.endswith('obstacle') else '<f2' if path.stem.endswith(('wetness','compaction')) else '<f4'
        av,bv=np.frombuffer(ad,dtype=dtype),np.frombuffer(bd,dtype=dtype)
        changed=np.flatnonzero(av!=bv)
        rows.append({'tick':int(path.name.split('_')[3]),'field':'_'.join(path.stem.split('_')[4:]),'byte_equal':ad==bd,'changed_components':len(changed),'maximum':float(np.max(np.abs(av.astype('f8')-bv.astype('f8')))),'sources':[{'path':p.name,'size':len(d),'sha256':hashlib.sha256(d).hexdigest()} for p,d in ((path,ad),(peer,bd))],'samples':[{'component':int(i),'active':float(av[i]),'worker':float(bv[i])} for i in changed[:8]]})
    sand=[]
    for tick in range(1,20):
        paths=[root/('trace_%s_tick_%d.bin'%(label,tick)) for label in ('active','worker')]
        ad,bd=[p.read_bytes() for p in paths]
        av,bv=np.frombuffer(ad,dtype='<f4'),np.frombuffer(bd,dtype='<f4')
        sand.append({'tick':tick,'byte_equal':ad==bd,'changed_cells':int(np.count_nonzero(av!=bv))})
    result={'scope':'GPU-copy diagnostic variant; not a default first-pass claim','native_pairs':len(rows),'all_equal_ticks':[tick for tick in sorted({r['tick'] for r in rows}) if all(r['byte_equal'] for r in rows if r['tick']==tick)],'first_sand_difference':next(r['tick'] for r in sand if not r['byte_equal']),'sand':sand,'native':rows}
    (root/'native_trace_analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(name, 'pairs',len(rows),'equal complete ticks',result['all_equal_ticks'],'first sand',result['first_sand_difference'])
