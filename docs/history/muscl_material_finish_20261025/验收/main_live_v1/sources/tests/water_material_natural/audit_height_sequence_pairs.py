"""Compare identical completed ticks against pre-fix sequence, including actual shader clocks."""
import json,sys
from pathlib import Path
import numpy as np
from PIL import Image

p=Path(sys.argv[1]).resolve()
old=Path(sys.argv[2]).resolve()
d=json.loads((p/'style_sequence.json').read_text())
b=json.loads((old/'style_sequence.json').read_text())
assert [f['tick'] for f in d['frames']]==[f['tick'] for f in b['frames']]
raw={}
clocks={}
for tick,c in d['checkpoints'].items():
    raw[tick]={name:value==b['checkpoints'][tick]['hashes'][name] for name,value in c['hashes'].items()}
    assert all(raw[tick].values())
    clocks[tick]=c['shader_clocks']
    assert all(abs(float(v)-int(tick)/30)<1e-5 for v in clocks[tick].values())
    assert c['effective_style']['natural_height_surface_normal'] is True
rows={}
for cam in ['close','oblique','grazing']:
    rows[cam]=[]
    for a,z in zip(d['frames'],b['frames']):
        x=np.asarray(Image.open(a['images'][cam]['path']).convert('RGB')).astype(int)
        y=np.asarray(Image.open(z['images'][cam]['path']).convert('RGB')).astype(int)
        delta=np.abs(x-y).max(2)
        rows[cam].append({'tick':a['tick'],'time_s':a['time_s'],'changed_pixels_over_one_bit':int((delta>1).sum()),'max_rgb_delta':int(delta.max())})
result={'all_sample_ticks_match':True,'raw_checkpoint_pairs':raw,'actual_shader_clocks':clocks,
    'height_normal_consumed_at_all_checkpoints':True,'cameras':rows,
    'limits':'Seven authority checkpoints, not all 1801 simulation ticks. RGB differences report the single shading-normal change; they are not a subjective acceptance threshold or a cost result.'}
(p/'height_pair_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'all_sample_ticks_match':True,'raw_checkpoints':len(raw),'fields_per_checkpoint':7,'actual_shader_clocks_match':True,'height_normal_consumed':True}))
