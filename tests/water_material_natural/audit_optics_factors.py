import json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
out=Path(sys.argv[1]).resolve()
run=json.loads((out/'process_result.json').read_text())
assert run['exit_code']==0 and run['sources_unchanged_during_run']
d=json.loads((out/'optics_factors.json').read_text())
assert all(d['fields_unchanged'].values())
def load(case,debug,cam):
    return np.asarray(Image.open(d['cases'][case]['images'][f'{debug}_{cam}']['path']).convert('RGB')).astype(np.int16)
rows={}
for cam in ['oblique','close','grazing']:
    board=Image.new('RGB',(1920,620),(24,24,24));draw=ImageDraw.Draw(board)
    rows[cam]={}
    base=load('baseline',0,cam);trans=load('baseline',4,cam)
    for i,(case,desc) in enumerate(d['cases'].items()):
        a=load(case,0,cam);b=load(case,4,cam)
        x=i%4*480;y=i//4*310
        board.paste(Image.fromarray(a.astype(np.uint8)).resize((480,270)),(x,y+25))
        draw.text((x+5,y+5),f'{cam} {case} {desc["changes"]}',fill='white')
        rows[cam][case]={'production_changed_over_one_bit':int((np.abs(a-base).max(2)>1).sum()),
            'transmission_changed_over_one_bit':int((np.abs(b-trans).max(2)>1).sum()),
            'mean_production_delta':float(np.abs(a-base).mean())}
    board.save(out/f'factors_{cam}.png')
controls=all(rows[cam][case]['transmission_changed_over_one_bit']==0
    for cam in rows for case in ['scatter_075','scatter_050','preserve_off'])
result={'fields_unchanged':d['fields_unchanged'],'cameras':rows,
        'scatter_preserve_do_not_change_transmission':controls,
        'scope':'Single-factor contribution controls; visual choice requires board review and subsequent combined candidate.'}
(out/'factor_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
