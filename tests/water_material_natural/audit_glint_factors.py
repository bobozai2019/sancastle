import json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
p=Path(sys.argv[1]).resolve();d=json.loads((p/'glint_factors.json').read_text());r=json.loads((p/'process_result.json').read_text())
assert r['exit_code']==0 and r['engine_error_free'] and r['sources_unchanged_during_run'] and all(d['fields_unchanged'].values())
rows={}
for cam in ['close','oblique','grazing','sunward']:
    get=lambda c,n:np.asarray(Image.open(d['cases'][c]['images'][f'{n}_{cam}']['path']).convert('RGB')).astype(int)
    mask=get('disabled',1).max(2)<=1
    rows[cam]={'zero_matches_disabled':all(np.abs(get('disabled',n)-get('gain00',n)).max()<=1 for n in [0,1]),
        'debug_black_water_pixels':int(mask.sum()),'cases':{}}
    if cam!='sunward':
        old=np.asarray(Image.open(p.parent/'t05_reflection_oriented_v1'/f'perturbed_debug0_{cam}.png').convert('RGB')).astype(int)
        rows[cam]['baseline_max_delta']=int(np.abs(get('baseline',0)-old).max())
    for debug in [0,1]:
        board=Image.new('RGB',(1920,620),(24,24,24));draw=ImageDraw.Draw(board)
        for i,case in enumerate(d['cases']):
            a=get(case,debug);x=i%4*480;y=i//4*310
            board.paste(Image.fromarray(a.astype(np.uint8)).resize((480,270)),(x,y+25));draw.text((x+5,y+5),f'{cam} {case} debug{debug}',fill='white')
            if debug==1:
                v=a.max(2)[mask]
                rows[cam]['cases'][case]={'solar_pixels_over_1':int((v>1).sum()),'solar_pixels_over_32':int((v>32).sum()),
                    'solar_pixels_over_128':int((v>128).sum()),'max_solar_8bit':int(v.max()),
                    'production_changed_pixels':int((np.abs(get(case,0)-get('baseline',0)).max(2)>1).sum())}
        board.save(p/f'glint_debug{debug}_{cam}.png')
result={'cameras':rows,'zero_matches_disabled':all(v['zero_matches_disabled'] for v in rows.values()),
    'baseline_equivalent':all(rows[c]['baseline_max_delta']==0 for c in ['close','oblique','grazing']),
    'fields_unchanged':d['fields_unchanged'],'limits':'Solar-only image is a rendered contribution, not physical radiance or material roughness. Normal gain also changes other optical terms in production.'}
(p/'glint_factor_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
