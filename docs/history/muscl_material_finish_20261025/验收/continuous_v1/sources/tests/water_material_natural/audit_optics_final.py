import json,re,sys
from pathlib import Path
import numpy as np
from PIL import Image
out=Path(sys.argv[1]).resolve();m=json.loads((out/'manifest.json').read_text());d=json.loads((out/'optics_final.json').read_text())
run=json.loads((out/'process_result.json').read_text());assert run['exit_code']==0 and run['sources_unchanged_during_run']
raw=lambda n:np.fromfile(out/f'{n}.bin',dtype='<f4').reshape(256,256)
depth=raw('water');bed=raw('rock')+raw('sand');dry=depth<=.001
interior=dry.copy()
for dz in [-1,0,1]:
    for dx in [-1,0,1]:interior &= np.roll(np.roll(dry,dz,0),dx,1)
interior[[0,-1],:]=False;interior[:,[0,-1]]=False
z,x=np.indices(depth.shape);points=np.stack(((x+.5)/256*32-16,bed,(z+.5)/256*32-16),-1).reshape(-1,3)
rows={}
for camera,desc in m['cameras'].items():
    selected=np.asarray(Image.open(d['images']['selected'][camera]['path']).convert('RGB')).astype(int)
    target=np.asarray(Image.open(out.parent/'t03_unrefracted_factors'/f'deep_040_debug0_{camera}.png').convert('RGB')).astype(int)
    reference=np.asarray(Image.open(d['images']['bed_only'][camera]['path']).convert('RGB')).astype(int)
    diagnostic=np.asarray(Image.open(out/f'legacy_debug1_{camera}.png').convert('RGB')).astype(int)
    values=np.array([float(v) for v in re.findall(r'[-+]?[0-9]*\.?[0-9]+',desc['transform'].split('(',1)[1])])
    view=(points-values[9:])@values[:9].reshape(3,3);t=np.tan(np.radians(desc['fov'])/2)
    px=np.rint((view[:,0]/-view[:,2]/(t*1280/720)*.5+.5)*1280).astype(int)
    py=np.rint((.5-view[:,1]/-view[:,2]/t*.5)*720).astype(int)
    visible=(view[:,2]<-.05)&(px>=0)&(px<1280)&(py>=0)&(py<720)&interior.ravel()
    ids=np.flatnonzero(visible);qx=px[ids];qy=py[ids]
    # Runtime diagnostic leaves opaque bed unchanged where no water fragment draws.
    uncovered=np.abs(diagnostic[qy,qx]-reference[qy,qx]).max(1)<=1
    drydelta=np.abs(selected[qy,qx]-reference[qy,qx]).max(1)
    rows[camera]={'selected_vs_reviewed_factor_max_delta':int(np.abs(selected-target).max()),
        'selected_vs_reviewed_factor_over_one_bit':int((np.abs(selected-target).max(2)>1).sum()),
        'projected_dry_interior_points':int(len(ids)),
        'runtime_uncovered_dry_points':int(uncovered.sum()),
        'dry_points_changed_over_one_bit':int((uncovered&(drydelta>1)).sum())}
result={'cameras':rows,'reviewed_choice_reproduced':all(v['selected_vs_reviewed_factor_over_one_bit']==0 for v in rows.values()),
    'visible_dry_negative':all(v['runtime_uncovered_dry_points']>0 and v['dry_points_changed_over_one_bit']==0 for v in rows.values()),
    'effective_optics':d['effective_optics'],
    'limits':'Dry point projection excludes occluded/water-covered points; does not claim all hidden dry cells were inspected. Crest/curl omitted from the CPU projector.'}
(out/'final_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
