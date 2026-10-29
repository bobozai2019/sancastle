import json, sys, re
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

p = Path(sys.argv[1]).resolve()
d = json.loads((p/'macro_normal_cases.json').read_text())
r = json.loads((p/'process_result.json').read_text())
assert r['exit_code'] == 0 and r['engine_error_free'] and r['sources_unchanged_during_run']
assert all(d['fields_unchanged'].values())
modes = sorted({int(re.match(r'mode(\d+)',key)[1]) for key in d['cases']})
rows = {}
for cam in ['close','oblique','grazing']:
    get = lambda key: np.asarray(Image.open(d['cases'][key]['images'][cam]['path']).convert('RGB')).astype(int)
    direct = np.asarray(Image.open(p/f'{cam}.png').convert('RGB')).astype(int)
    zero = get('mode0_detail1_debug0')
    rows[cam] = {'default0_max_delta':int(np.abs(direct-zero).max()),'mode_results':{}}
    board = Image.new('RGB',(1280,len(modes)*560),(24,24,24))
    draw = ImageDraw.Draw(board)
    for row, mode in enumerate(modes):
        for detail in [0,1]:
            key = f'mode{mode}_detail{detail}_debug'
            normal = get(key+'1'); production = get(key+'0')
            # This ROI was frozen in G0. Counts are visual encoded-color diagnostics, not a geometric correctness gate.
            q = normal[380:460,665:900]
            rows[cam]['mode_results'][f'mode{mode}_detail{detail}'] = {
                'production_change_pixels_over_one_bit':int((np.abs(production-zero).max(2)>1).sum()),
                'magenta_normal_color_pixels_in_front_roi':int(((q[:,:,1]<50)&(q[:,:,0]>120)&(q[:,:,2]>120)).sum())}
        for debug in [0,1]:
            image = Image.fromarray(get(f'mode{mode}_detail1_debug{debug}').astype('uint8'))
            board.paste(image.resize((640,360)),(debug*640,row*560+25))
            draw.text((debug*640+5,row*560+5),f'{cam} mode{mode} debug{debug}',fill='white')
            board.paste(image.crop((665,380,900,460)).resize((640,160)),(debug*640,row*560+390))
    board.save(p/f'macro_modes_{cam}.png')
result = {'cameras':rows,'default0_matches_direct':all(v['default0_max_delta']<=1 for v in rows.values()),
    'fields_unchanged':d['fields_unchanged'],
    'limits':'Color counts in frozen front ROIs are diagnostics, not physical masks or acceptance thresholds. Check actual normal colors, shore facets, affected guards and continuous samples before selection.'}
(p/'macro_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
