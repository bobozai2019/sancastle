"""Verify exact simulation timestamps and paired frame artifacts; retain preview."""
import json
from pathlib import Path
import hashlib
from PIL import Image,ImageDraw
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'test_output/water_material_natural/t01_sequence'
manifest=json.loads((out/'manifest.json').read_text())
frames=manifest['frames']
assert len(frames)==302
metrics={}
for tick in range(360,511):
    pair=[f for f in frames if f['tick']==tick]
    assert [p['mode'] for p in pair]==[1,2]
    assert all(abs(p['time_s']-tick/30)<1e-12 and p['generation']==1 for p in pair)
    assert pair[0]['revision']==pair[1]['revision']
    for p in pair:
        path=Path(p['path'])
        assert hashlib.sha256(path.read_bytes()).hexdigest()==p['sha256']
        assert Image.open(path).size==(1280,720)
    arrays=[np.array(Image.open(p['path'])).astype(float) for p in pair]
    metrics[tick]={'paired_mean_abs_rgb':float(np.abs(arrays[0]-arrays[1]).mean())}
board=Image.new('RGB',(1280,6*388),(28,30,33));draw=ImageDraw.Draw(board)
for row,tick in enumerate(range(360,511,30)):
    for col,mode in enumerate([1,2]):
        board.paste(Image.open(out/f'mode{mode}_{tick-360:04d}.png').resize((640,360)),(col*640,row*388+28))
        draw.text((col*640+8,row*388+8),f'tick {tick} / {tick/30:.2f}s / '+('legacy' if mode==1 else 'texture'),fill='white')
board.save(out/'timeline_board.png')
result={'pass':True,'verified_frames':302,'ticks':[360,510],'time_s':[12,17],
        'paired_state_revision_equal':True,'clock_matches_tick':True,
        'json_time_tolerance_s':1e-12,'max_json_time_error_s':max(abs(p['time_s']-p['tick']/30) for p in frames),'metrics':metrics,
        'scope':'offline 30fps simulation time, no real-time performance assertion',
        'visual_review_required':'timeline and intermediate PNGs; byte/hash/clock checks do not certify aesthetics'}
(out/'audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='metrics'}))
