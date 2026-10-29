import json,re,sys
from pathlib import Path
import numpy as np
from PIL import Image
out=Path(sys.argv[1]).resolve();m=json.loads((out/'manifest.json').read_text());d=json.loads((out/'layer_dry.json').read_text())
run=json.loads((out/'process_result.json').read_text());assert run['exit_code']==0 and run['sources_unchanged_during_run']
assert all(d['fields_unchanged'].values())
raw=lambda n:np.fromfile(out/f'{n}.bin',dtype='<f4').reshape(256,256)
depth=raw('water');bed=raw('rock')+raw('sand');dry=depth<=.001
interior=np.logical_and.reduce([np.roll(np.roll(dry,z,0),x,1) for z in [-1,0,1] for x in [-1,0,1]])
interior[[0,-1],:]=False;interior[:,[0,-1]]=False
z,x=np.indices(depth.shape);points=np.stack(((x+.5)/8-16,bed,(z+.5)/8-16),-1).reshape(-1,3)
rows={}
for camera,desc in m['cameras'].items():
    load=lambda name:np.asarray(Image.open(d['images'][name][camera]['path']).convert('RGB')).astype(int)
    reference=load('bed_only');diagnostic=load('depth_labels')
    values=np.array([float(v) for v in re.findall(r'[-+]?[0-9]*\.?[0-9]+',desc['transform'].split('(',1)[1])])
    view=(points-values[9:])@values[:9].reshape(3,3);t=np.tan(np.radians(desc['fov'])/2)
    px=np.rint((view[:,0]/-view[:,2]/(t*1280/720)*.5+.5)*1280).astype(int)
    py=np.rint((.5-view[:,1]/-view[:,2]/t*.5)*720).astype(int)
    ids=np.flatnonzero((view[:,2]<-.05)&(px>=0)&(px<1280)&(py>=0)&(py<720)&interior.ravel())
    qx=px[ids];qy=py[ids];uncovered=np.abs(diagnostic[qy,qx]-reference[qy,qx]).max(1)<=1
    rows[camera]={'runtime_uncovered_dry_points':int(uncovered.sum()),'layers':{}}
    for name in ['all_on','water_only','foam_only','contact_only']:
        a=load(name);changed=uncovered&(np.abs(a[qy,qx]-reference[qy,qx]).max(1)>1)
        rows[camera]['layers'][name]={'changed_dry_points':int(changed.sum()),
            'pixels':[[int(qx[i]),int(qy[i])] for i in np.flatnonzero(changed)]}
result={'cameras':rows,'water_dry_negative':all(r['runtime_uncovered_dry_points']>0 and r['layers']['water_only']['changed_dry_points']==0 for r in rows.values()),
    'fields_unchanged':d['fields_unchanged'],'limits':'Visible dry raw-cell interiors only; foam/contact are attributed separately, not silently excluded from the full visual result.'}
(out/'layer_dry_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
