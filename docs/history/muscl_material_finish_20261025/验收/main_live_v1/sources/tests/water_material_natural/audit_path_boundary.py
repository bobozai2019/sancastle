import json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
out=Path(sys.argv[1]).resolve();d=json.loads((out/'path_boundary.json').read_text())
run=json.loads((out/'process_result.json').read_text());assert run['exit_code']==0 and run['sources_unchanged_during_run']
assert all(d['fields_unchanged'].values())
load=lambda case,debug,cam:np.asarray(Image.open(d['cases'][case]['images'][f'{debug}_{cam}']['path']).convert('RGB')).astype(np.int16)
rows={}
for cam in ['oblique','close','grazing']:
    board=Image.new('RGB',(1600,820),(24,24,24));draw=ImageDraw.Draw(board)
    rows[cam]={}
    for col,(case,desc) in enumerate(d['cases'].items()):
        for row,debug in enumerate([0,2,3,4]):
            a=load(case,debug,cam)
            board.paste(Image.fromarray(a.astype(np.uint8)).resize((320,180)),(col*320,row*205+25))
            draw.text((col*320+5,row*205+5),f'{case} {cam} debug{debug}',fill='white')
        prod=load(case,0,cam)
        reference=out.parent/'t03_factors_v2'/f'deep_040_debug0_{cam}.png'
        old=np.asarray(Image.open(reference).convert('RGB')).astype(np.int16)
        rows[cam][case]={'production_changed_vs_current_over_one_bit':int((np.abs(prod-old).max(2)>1).sum())}
    board.save(out/f'boundary_{cam}.png')
# Localize transmission discontinuities in the far-water ROI before selecting a route.
group=np.asarray(Image.open(out.parent/'t03_path_v2'/'legacy_debug1_oblique.png').convert('RGB'))
water=(group[:,:,2]>245)&(group[:,:,:2].max(2)<5)
roi=np.zeros(water.shape,bool);roi[220:450,250:600]=True;water &= roi
current_flags=load('current',3,'oblique')[:,:,0]>250
for case in d['cases']:
    grey=load(case,4,'oblique')[:,:,0]
    jumps=0;at_guard=0
    for axis in [0,1]:
        shift=np.roll(grey,1,axis);both=water&np.roll(water,1,axis)
        edge=both&(np.abs(grey-shift)>20)
        jumps+=int(edge.sum())
        at_guard+=int((edge&(current_flags!=np.roll(current_flags,1,axis))).sum())
    rows['oblique'][case]['far_roi_transmission_jumps_over20']=jumps
    rows['oblique'][case]['jumps_at_current_guard_transition']=at_guard
result={'cases':rows,'fields_unchanged':d['fields_unchanged'],
    'scope':'Diagnostic UV/guard attribution and frozen ROI jump counts, not a substitute for visual review or universal geometry correctness.'}
(out/'boundary_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
