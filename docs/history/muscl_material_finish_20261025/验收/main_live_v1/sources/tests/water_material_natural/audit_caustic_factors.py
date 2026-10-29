import json,sys,re
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
p=Path(sys.argv[1]).resolve();d=json.loads((p/'caustic_factors.json').read_text());r=json.loads((p/'process_result.json').read_text())
assert r['exit_code']==0 and r['engine_error_free'] and r['sources_unchanged_during_run'] and all(d['fields_unchanged'].values())
m=json.loads((p/'manifest.json').read_text())
raw=lambda n:np.fromfile(p/f'{n}.bin',dtype='<f4').reshape(256,256)
depth=raw('water');bed=raw('rock')+raw('sand');dry=depth<=.001
interior=np.logical_and.reduce([np.roll(np.roll(dry,z,0),x,1) for z in [-1,0,1] for x in [-1,0,1]])
interior[[0,-1],:]=False;interior[:,[0,-1]]=False
z,x=np.indices(depth.shape);points=np.stack(((x+.5)/8-16,bed,(z+.5)/8-16),-1).reshape(-1,3)
rows={}
for cam,camera in m['cameras'].items():
    get=lambda case,mode:np.asarray(Image.open(d['cases'][case]['images'][f'{mode}_{cam}']['path']).convert('RGB')).astype(int)
    old=np.asarray(Image.open(p.parent/'t05_reflection_oriented_v1'/f'perturbed_debug0_{cam}.png').convert('RGB')).astype(int)
    assert np.abs(get('baseline','production')-old).max()==0
    values=np.array([float(v) for v in re.findall(r'[-+]?[0-9]*\.?[0-9]+',camera['transform'].split('(',1)[1])])
    view=(points-values[9:])@values[:9].reshape(3,3);t=np.tan(np.radians(camera['fov'])/2)
    px=np.rint((view[:,0]/-view[:,2]/(t*1280/720)*.5+.5)*1280).astype(int)
    py=np.rint((.5-view[:,1]/-view[:,2]/t*.5)*720).astype(int)
    ids=np.flatnonzero((view[:,2]<-.05)&(px>=0)&(px<1280)&(py>=0)&(py<720)&interior.ravel())
    qx=px[ids];qy=py[ids]
    reference=get('baseline','bed_only')
    labels=np.asarray(Image.open(p.parent/'t04_combination_v1'/f'depth_labels_{cam}.png').convert('RGB')).astype(int)
    uncovered=np.abs(labels[qy,qx]-reference[qy,qx]).max(1)<=1
    rows[cam]={'cases':{},'zero_gain_matches_disabled':all(np.abs(get('gain00',mode)-get('disabled',mode)).max()<=1 for mode in ['production','bed_only']),
        'visible_uncovered_dry_points':int(uncovered.sum())}
    for mode in ['production','bed_only']:
        board=Image.new('RGB',(1920,620),(24,24,24));draw=ImageDraw.Draw(board)
        for i,case in enumerate(d['cases']):
            a=get(case,mode);delta=np.abs(a-get('baseline',mode)).max(2);x=i%4*480;y=i//4*310
            board.paste(Image.fromarray(a.astype(np.uint8)).resize((480,270)),(x,y+25));draw.text((x+5,y+5),f'{cam} {case} {mode}',fill='white')
            dry_changed=uncovered&(np.abs(a[qy,qx]-get('baseline',mode)[qy,qx]).max(1)>1)
            rows[cam]['cases'][f'{case}_{mode}']={'changed_pixels':int((delta>1).sum()),'max_delta':int(delta.max()),'changed_dry_points':int(dry_changed.sum())}
        board.save(p/f'caustics_{mode}_{cam}.png')
result={'cameras':rows,'baseline_equivalent':True,'zero_gain_matches_disabled':all(v['zero_gain_matches_disabled'] for v in rows.values()),
    'dry_points_unchanged':all(c['changed_dry_points']==0 for v in rows.values() for c in v['cases'].values()),
    'fields_unchanged':d['fields_unchanged'],'limits':'Existing bed UV caustic factors, fixed completed state. No claim of physical caustics or final temporal/cost gate.'}
(p/'caustic_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
