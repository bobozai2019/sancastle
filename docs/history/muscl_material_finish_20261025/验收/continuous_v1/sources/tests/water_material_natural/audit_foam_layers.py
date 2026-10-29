import json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
out=Path(sys.argv[1]).resolve();d=json.loads((out/'foam_layers.json').read_text())
run=json.loads((out/'process_result.json').read_text())
assert run['exit_code']==0 and run['engine_error_free'] and run['sources_unchanged_during_run']
assert all(d['fields_unchanged'].values())
load=lambda case,cam:np.asarray(Image.open(d['cases'][case]['images'][cam]['path']).convert('RGB')).astype(int)
rows={}
for cam in ['oblique','close','grazing']:
    all_on=load('all_on',cam)
    old=np.asarray(Image.open(out.parent/'t03_selected_final'/f'selected_{cam}.png').convert('RGB')).astype(int)
    rows[cam]={'baseline_max_delta':int(np.abs(all_on-old).max()),
        'baseline_pixels_over_one_bit':int((np.abs(all_on-old).max(2)>1).sum()),'contributions':{}}
    board=Image.new('RGB',(1920,620),(24,24,24));draw=ImageDraw.Draw(board)
    base=load('all_off',cam)
    for i,case in enumerate(d['cases']):
        a=load(case,cam);x=i%4*480;y=i//4*310
        board.paste(Image.fromarray(a.astype(np.uint8)).resize((480,270)),(x,y+25))
        draw.text((x+5,y+5),f'{cam} {case}',fill='white')
        if case.endswith('_only'):
            delta=np.abs(a-base).max(2)
            rows[cam]['contributions'][case]={'changed_pixels_over_one_bit':int((delta>1).sum()),
                'max_channel_delta':int(delta.max())}
    board.save(out/f'layers_{cam}.png')
result={'baseline_equivalent':all(v['baseline_pixels_over_one_bit']==0 for v in rows.values()),
    'layers_effective':all(c['changed_pixels_over_one_bit']>0 for r in rows.values() for c in r['contributions'].values()),
    'cameras':rows,'fields_unchanged':d['fields_unchanged'],'effective_foam':d['effective_foam'],
    'scope':'Eight actual shader layer switches, fixed state; does not prove size/cluster improvement or dynamic foam lifecycle.'}
(out/'layer_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
