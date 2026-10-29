"""Audit path-only controls and produce camera boards; no visual gate by export."""
import json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
out=Path(sys.argv[1]).resolve()
run=json.loads((out/'process_result.json').read_text())
assert run['exit_code']==0 and run['sources_unchanged_during_run']
data=json.loads((out/'optics_path.json').read_text())
assert all(data['fields_unchanged'].values())
def load(case,debug,camera):
    return np.asarray(Image.open(data['cases'][case]['images'][f'{debug}_{camera}']['path']).convert('RGB')).astype(np.int16)
rows={}
board=Image.new('RGB',(1280,3*250),(24,24,24))
draw=ImageDraw.Draw(board)
for i,cam in enumerate(['oblique','close','grazing']):
    native=load('native',0,cam);legacy=load('legacy',0,cam);new=load('reconstructed',0,cam)
    delta=np.abs(native-legacy)
    group=load('legacy',1,cam)
    masks={name:(group[:,:,c]>245)&(np.delete(group,c,axis=2).max(axis=2)<5) for name,c in [('shallow',0),('mid',1),('deep',2)]}
    fallback=load('reconstructed',3,cam)
    rows[cam]={'legacy_vs_native':{'max_channel_delta':int(delta.max()),'pixels_over_one_bit':int((delta.max(axis=2)>1).sum())},
        'production_changed_over_one_bit':int((np.abs(new-legacy).max(axis=2)>1).sum()),
        'fallback_pixels':{name:int((fallback[:,:,c]>245).sum()) for name,c in [('foreground',0),('edge',1),('invalid_path',2)]},
        'depth_groups':{}}
    for name,mask in masks.items():
        oldpath=load('legacy',2,cam)[:,:,0];newpath=load('reconstructed',2,cam)[:,:,0]
        oldtrans=load('legacy',4,cam)[:,:,0];newtrans=load('reconstructed',4,cam)[:,:,0]
        rows[cam]['depth_groups'][name]={'pixels':int(mask.sum()),'legacy_path_debug_mean':float(oldpath[mask].mean()) if mask.any() else None,
            'new_path_debug_mean':float(newpath[mask].mean()) if mask.any() else None,
            'legacy_transmission_debug_mean':float(oldtrans[mask].mean()) if mask.any() else None,
            'new_transmission_debug_mean':float(newtrans[mask].mean()) if mask.any() else None}
    for j,(case,debug) in enumerate([('legacy',0),('reconstructed',0),('reconstructed',1),('reconstructed',3)]):
        img=Image.fromarray(load(case,debug,cam).astype(np.uint8)).resize((320,180))
        board.paste(img,(j*320,i*250+25));draw.text((j*320+5,i*250+5),f'{cam} {case} debug{debug}',fill='white')
board.save(out/'path_board.png')
result={'fields_unchanged':data['fields_unchanged'],'cameras':rows,
    'legacy_equivalent':all(v['legacy_vs_native']['pixels_over_one_bit']==0 for v in rows.values()),
    'scope':'Diagnostic group pixels are water-surface depth labels, not independent proof of bed depth or subjective visual acceptance.'}
(out/'path_audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
