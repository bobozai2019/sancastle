"""Cross-check authority cell groups against camera-projected surface labels.

Cell centers use bed+water+bias, without visual crest; this checks interior group
identity only, not exact wave/bed triangulation or refraction geometry.
"""
import json,re,sys
from pathlib import Path
import numpy as np
from PIL import Image
out=Path(sys.argv[1]).resolve()
m=json.loads((out/'manifest.json').read_text())
data=json.loads((out/'optics_path.json').read_text())
raw=lambda n:np.fromfile(out/f'{n}.bin',dtype='<f4').reshape(256,256)
depth=raw('water');bed=raw('rock')+raw('sand')
group=np.where(depth<.02,-1,np.where(depth<.08,0,np.where(depth<.20,1,2)))
interior=np.ones((256,256),bool)
for dz in [-1,0,1]:
    for dx in [-1,0,1]:interior &= group==np.roll(np.roll(group,dz,0),dx,1)
interior[[0,-1],:]=False;interior[:,[0,-1]]=False
z,x=np.indices(depth.shape)
points=np.stack(((x+.5)/256*32-16,bed+depth+.003,(z+.5)/256*32-16),-1).reshape(-1,3)
rows={}
for camera,desc in m['cameras'].items():
    nums=np.array([float(v) for v in re.findall(r'[-+]?[0-9]*\.?[0-9]+',desc['transform'].split('(',1)[1])])
    basis=nums[:9].reshape(3,3);origin=nums[9:]
    # var_to_str emits the Basis matrix in row order, not three basis columns.
    view=(points-origin)@basis
    h,w=720,1280;t=np.tan(np.radians(desc['fov'])/2)
    px=np.rint((view[:,0]/-view[:,2]/(t*w/h)*.5+.5)*w).astype(int)
    py=np.rint((.5-view[:,1]/-view[:,2]/t*.5)*h).astype(int)
    visible=(view[:,2]<-.05)&(px>=0)&(px<w)&(py>=0)&(py<h)&interior.ravel()&(group.ravel()>=0)
    ids=np.flatnonzero(visible)
    img=np.asarray(Image.open(data['cases']['legacy']['images'][f'1_{camera}']['path']).convert('RGB'))
    rgb=img[py[ids],px[ids]].astype(int)
    observed=rgb.argmax(axis=1)
    pure=(rgb.max(axis=1)>245)&(rgb.sum(axis=1)-rgb.max(axis=1)<10)
    expected=group.ravel()[ids]
    rows[camera]={'sampled_interior_cells':int(len(ids)),'pure_visible_depth_labels':int(pure.sum()),
        'matching_labels':int((pure&(expected==observed)).sum()),'mismatching_labels':int((pure&(expected!=observed)).sum()),
        'matching_fraction':float((expected[pure]==observed[pure]).mean()) if pure.any() else None,
        'by_group':{n:int((pure&(expected==c)).sum()) for n,c in [('shallow',0),('mid',1),('deep',2)]}}
result={'cameras':rows,'method':'Authority water bins at camera-projected 3x3 homogeneous cell interiors, bed+water+bias .003m',
    'limits':'Visual crest/curl/render triangulation omitted; excludes occluded/non-pure pixels; residual mismatches are retained, not a precise surface reconstruction PASS.'}
(out/'depth_projection.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
