import json,sys
from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np
p=Path(sys.argv[1]);d=json.loads((p/'reflection_foreground.json').read_text());r=json.loads((p/'process_result.json').read_text())
assert r['exit_code']==0 and r['engine_error_free'] and r['sources_unchanged_during_run'] and all(d['fields_unchanged'].values())
rows={}
for cam in ['close','oblique','grazing']:
    get=lambda k:np.asarray(Image.open(d['cases'][k][cam]['path']).convert('RGB')).astype(int)
    a=get('mask');candidate=(a[:,:,0]>180)&(a[:,:,1]<90)&(a[:,:,2]>160)
    colors,counts=np.unique(a[candidate],axis=0,return_counts=True)
    color=colors[counts.argmax()];mask=(a==color).all(2)
    inside=np.logical_and.reduce([np.roll(np.roll(mask,z,0),x,1) for z in [-1,0,1] for x in [-1,0,1]])
    inside[[0,-1],:]=False;inside[:,[0,-1]]=False
    present=np.abs(get('present_on')-get('present_off')).max(2);hidden=np.abs(get('hidden_on')-get('hidden_off')).max(2)
    rows[cam]={'opaque_marker_rgb':color.tolist(),'opaque_interior_pixels':int(inside.sum()),
        'reflection_leak_pixels':int((inside&(present>1)).sum()),'actual_hidden_reflection_behind_occluder_pixels':int((inside&(hidden>1)).sum())}
    b=Image.new('RGB',(1920,310),(24,24,24));draw=ImageDraw.Draw(b)
    for i,k in enumerate(['present_on','present_off','mask','hidden_on']):
        b.paste(Image.fromarray(get(k).astype(np.uint8)).resize((480,270)),(i*480,25))
        draw.text((i*480+5,5),cam+' '+k,fill='white')
    b.save(p/f'foreground_{cam}.png')
r={'cameras':rows,'pass':all(v['opaque_interior_pixels']>0 and v['reflection_leak_pixels']==0 and v['actual_hidden_reflection_behind_occluder_pixels']>5 for v in rows.values()),
    'fields_unchanged':d['fields_unchanged'],'scope':d['scope']}
(p/'foreground_audit.json').write_text(json.dumps(r,indent=2));print(json.dumps(r))
