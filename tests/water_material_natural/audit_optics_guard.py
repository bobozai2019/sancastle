import json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
out=Path(sys.argv[1]).resolve()
data=json.loads((out/'optics_guard.json').read_text())
assert all(data['fields_unchanged'].values())
def load(case,debug,cam):
    return np.asarray(Image.open(data['cases'][case]['images'][f'{debug}_{cam}']['path']).convert('RGB')).astype(np.int16)
rows={}
board=Image.new('RGB',(1280,750),(24,24,24));draw=ImageDraw.Draw(board)
for i,cam in enumerate(['oblique','close','grazing']):
    flags=load('protected',3,cam)
    fore=flags[:,:,0]>250;edge=flags[:,:,1]>250
    guarded=load('protected',6,cam)
    raw=load('unguarded',6,cam);clamp=load('edge_clamp',6,cam)
    a=np.abs(guarded-raw).max(axis=2)>1;b=np.abs(guarded-clamp).max(axis=2)>1
    magenta=lambda v:(v[:,:,0]>150)&(v[:,:,2]>100)&(v[:,:,1]<60)
    rows[cam]={'foreground_flag_pixels':int(fore.sum()),'guard_changes':int(a.sum()),
        'guard_changes_outside_flag':int((a&~fore).sum()),'unprotected_magenta_leaks_removed':int((fore&magenta(raw)&~magenta(guarded)).sum()),
        'edge_flag_pixels':int(edge.sum()),'clamp_changes':int(b.sum()),'clamp_changes_outside_flag':int((b&~edge).sum())}
    if 'zero_refraction' in data['cases']:
        zero=load('zero_refraction',3,cam)
        rows[cam]['zero_refraction_foreground_pixels']=int((zero[:,:,0]>250).sum())
        rows[cam]['zero_refraction_invalid_path_pixels']=int((zero[:,:,2]>250).sum())
    for j,(case,debug) in enumerate([('protected',3),('protected',6),('unguarded',6),('edge_clamp',6)]):
        board.paste(Image.fromarray(load(case,debug,cam).astype(np.uint8)).resize((320,180)),(j*320,i*250+25))
        draw.text((j*320+5,i*250+5),f'{cam} {case} debug{debug}',fill='white')
board.save(out/'guard_board.png')
result={'cameras':rows,'fields_unchanged':data['fields_unchanged'],
    'localized':all(v['guard_changes_outside_flag']==0 and v['clamp_changes_outside_flag']==0 for v in rows.values()),
    'foreground_caster_effect_observed':any(v['unprotected_magenta_leaks_removed']>0 for v in rows.values()),
    'edge_effect_observed':all(v['clamp_changes']>0 for v in rows.values()),
    'scope':'Independent guard and edge-clamp controls; large base guard masks still require reconstruction-space attribution.'}
(out/'guard_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
