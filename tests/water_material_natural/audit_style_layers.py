import json,sys,re
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
p=Path(sys.argv[1]).resolve();d=json.loads((p/'style_layers.json').read_text());m=json.loads((p/'manifest.json').read_text());r=json.loads((p/'process_result.json').read_text())
assert r['exit_code']==0 and r['engine_error_free'] and r['sources_unchanged_during_run'] and all(d['fields_unchanged'].values())
raw=lambda n:np.fromfile(p/f'{n}.bin',dtype='<f4').reshape(256,256)
depth=raw('water');bed=raw('rock')+raw('sand');dry=depth<=.001
interior=np.logical_and.reduce([np.roll(np.roll(dry,z,0),x,1) for z in [-1,0,1] for x in [-1,0,1]])
interior[[0,-1],:]=False;interior[:,[0,-1]]=False
z,x=np.indices(depth.shape);points=np.stack(((x+.5)/8-16,bed,(z+.5)/8-16),-1).reshape(-1,3)
rows={}
for cam,camera in m['cameras'].items():
    get=lambda case:np.asarray(Image.open(d['cases'][case]['images'][cam]['path']).convert('RGB')).astype(int)
    direct=np.asarray(Image.open(p/f'{cam}.png').convert('RGB')).astype(int)
    assert np.abs(direct-get('all_on')).max()<=1
    values=np.array([float(v) for v in re.findall(r'[-+]?[0-9]*\.?[0-9]+',camera['transform'].split('(',1)[1])])
    view=(points-values[9:])@values[:9].reshape(3,3);t=np.tan(np.radians(camera['fov'])/2)
    px=np.rint((view[:,0]/-view[:,2]/(t*1280/720)*.5+.5)*1280).astype(int)
    py=np.rint((.5-view[:,1]/-view[:,2]/t*.5)*720).astype(int)
    ids=np.flatnonzero((view[:,2]<-.05)&(px>=0)&(px<1280)&(py>=0)&(py<720)&interior.ravel())
    qx=px[ids];qy=py[ids];base=get('bed_only')
    uncovered=np.abs(get('depth_labels')[qy,qx]-base[qy,qx]).max(1)<=1
    changed=uncovered&(np.abs(get('all_on')[qy,qx]-base[qy,qx]).max(1)>1)
    rows[cam]={'visible_uncovered_dry_points':int(uncovered.sum()),'changed_dry_points':int(changed.sum()),'contributions':{}}
    board=Image.new('RGB',(1920,930),(24,24,24));draw=ImageDraw.Draw(board)
    for i,case in enumerate(d['cases']):
        a=get(case);x=i%4*480;y=i//4*310
        board.paste(Image.fromarray(a.astype(np.uint8)).resize((480,270)),(x,y+25));draw.text((x+5,y+5),f'{cam} {case}',fill='white')
        if case in ['caustics_only','glint_only','foam_only','reflection_only']:
            delta=np.abs(a-get('all_features_off')).max(2)
            rows[cam]['contributions'][case]={'changed_pixels_over_one_bit':int((delta>1).sum()),'max_delta':int(delta.max())}
    board.save(p/f'style_layers_{cam}.png')
result={'cameras':rows,'direct_profile_matches_probe':True,
    'all_layers_effective':all(c['changed_pixels_over_one_bit']>0 for v in rows.values() for c in v['contributions'].values()),
    'dry_points_unchanged':all(v['visible_uncovered_dry_points']>0 and v['changed_dry_points']==0 for v in rows.values()),
    'fields_unchanged':d['fields_unchanged'],'effective_style':d['effective_style'],
    'limits':'Fixed completed state feature separation. Temporal and foreground/reflection boundaries with new fine gain still need their affected checks.'}
(p/'style_layer_audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items() if k!='effective_style'}))
