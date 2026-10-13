import json,re,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
out=Path(sys.argv[1]).resolve()
d=json.loads((out/'contact_height.json').read_text())
m=json.loads((out/'manifest.json').read_text())
run=json.loads((out/'process_result.json').read_text())
assert run['exit_code']==0 and run['engine_error_free'] and run['sources_unchanged_during_run']
assert all(d['fields_unchanged'].values())
raw=lambda n:np.fromfile(out/f'{n}.bin',dtype='<f4').reshape(256,256)
depth=raw('water');bed=raw('rock')+raw('sand');dry=depth<=.001
interior=np.logical_and.reduce([np.roll(np.roll(dry,z,0),x,1) for z in [-1,0,1] for x in [-1,0,1]])
interior[[0,-1],:]=False;interior[:,[0,-1]]=False
z,x=np.indices(depth.shape)
points=np.stack(((x+.5)/8-16,bed,(z+.5)/8-16),-1).reshape(-1,3)
rows={}
for camera,desc in m['cameras'].items():
    load=lambda h,mode:np.asarray(Image.open(d['cases'][h]['images'][f'{mode}_{camera}']['path']).convert('RGB')).astype(int)
    old=np.asarray(Image.open(out.parent/'t04_layers_v2'/f'all_on_{camera}.png').convert('RGB')).astype(int)
    assert np.abs(old-load('16','all_on')).max()==0
    no_contact=np.asarray(Image.open(out.parent/'t04_layers_v2'/f'contact_off_{camera}.png').convert('RGB')).astype(int)
    values=np.array([float(v) for v in re.findall(r'[-+]?[0-9]*\.?[0-9]+',desc['transform'].split('(',1)[1])])
    view=(points-values[9:])@values[:9].reshape(3,3);t=np.tan(np.radians(desc['fov'])/2)
    px=np.rint((view[:,0]/-view[:,2]/(t*1280/720)*.5+.5)*1280).astype(int)
    py=np.rint((.5-view[:,1]/-view[:,2]/t*.5)*720).astype(int)
    ids=np.flatnonzero((view[:,2]<-.05)&(px>=0)&(px<1280)&(py>=0)&(py<720)&interior.ravel())
    qx=px[ids];qy=py[ids]
    reference=load('16','bed_only');labels=load('16','depth_labels')
    uncovered=np.abs(labels[qy,qx]-reference[qy,qx]).max(1)<=1
    board=Image.new('RGB',(1920,620),(24,24,24));draw=ImageDraw.Draw(board)
    rows[camera]={}
    for i,h in enumerate(['16','8','4','3']):
        assert np.abs(load(h,'bed_only')-reference).max()==0
        assert np.abs(load(h,'depth_labels')-labels).max()==0
        production=load(h,'all_on');isolated=load(h,'contact_only')
        changed=uncovered&(np.abs(isolated[qy,qx]-reference[qy,qx]).max(1)>1)
        rows[camera][h]={'height_m':d['cases'][h]['height_m'],
            'isolated_changed_pixels':int((np.abs(isolated-reference).max(2)>1).sum()),
            'production_contact_changed_pixels':int((np.abs(production-no_contact).max(2)>1).sum()),
            'isolated_changed_dry_projection_points':int(changed.sum()),
            'dry_projection_pixels':[[int(qx[j]),int(qy[j])] for j in np.flatnonzero(changed)],
            'runtime_uncovered_dry_projection_points':int(uncovered.sum())}
        for y,mode in [(0,'all_on'),(310,'contact_only')]:
            a=load(h,mode)
            board.paste(Image.fromarray(a.astype(np.uint8)).resize((480,270)),(i*480,y+25))
            draw.text((i*480+5,y+5),f'{camera} h={h}mm {mode}',fill='white')
    board.save(out/f'height_{camera}.png')
result={'baseline_equivalent':True,'cameras':rows,'fields_unchanged':d['fields_unchanged'],'meshes':d['meshes'],
    'limits':'Screen-space contribution and dry-cell projection attribution. No assertion of exact foam/world correspondence or dynamic/dry-negative completion.'}
(out/'height_audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
