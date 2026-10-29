"""Show every sample as ROI time strips and adjacent frames around largest changes."""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

p = Path(sys.argv[1]).resolve()
d = json.loads((p/'style_sequence.json').read_text())
a = json.loads((p/'sequence_audit.json').read_text())
frames = d['frames']
for cam, record in a['cameras'].items():
    rois = record['roi_coordinates']
    strips = {name: [] for name in rois}
    for f in frames:
        image = np.asarray(Image.open(f['images'][cam]['path']).convert('RGB'))
        for name,(x,y,w,h) in rois.items():
            v = image[y:y+h,x:x+w]
            # Each column is one 100ms sample; preserve vertical position.
            strips[name].append(np.stack([v.mean(1),np.percentile(v,95,axis=1)],axis=0))
    board = Image.new('RGB',(1280,4*260),(24,24,24))
    draw = ImageDraw.Draw(board)
    for row,(name, samples) in enumerate(strips.items()):
        value = np.stack(samples,axis=2).astype(np.uint8)
        for kind in range(2):
            im = Image.fromarray(value[kind]).resize((1202,100))
            board.paste(im,(35,row*260+35+kind*110))
        draw.text((35,row*260+5),f'{cam} {name}: all 601 samples, 12..72s; mean / spatial p95 RGB',fill='white')
    board.save(p/f'temporal_strips_{cam}.png')
    for name,(x,y,w,h) in rois.items():
        selected = []
        for event in record['largest_mean_delta_ticks'][name]:
            if all(abs(event['tick']-t)>=30 for t in selected):selected.append(event['tick'])
            if len(selected)==4:break
        board = Image.new('RGB',(6*240,len(selected)*220),(24,24,24))
        draw = ImageDraw.Draw(board)
        for row,tick in enumerate(selected):
            index = (tick-frames[0]['tick'])//3
            for col,offset in enumerate([-3,-2,-1,0,1,2]):
                f = frames[max(0,min(len(frames)-1,index+offset))]
                im = Image.open(f['images'][cam]['path']).convert('RGB').crop((x,y,x+w,y+h))
                im.thumbnail((240,185));board.paste(im,(col*240,row*220+30))
                draw.text((col*240+5,row*220+5),f'{name} {f["time_s"]:.1f}s',fill='white')
        board.save(p/f'adjacent_{cam}_{name}.png')
print('All-sample ROI strips and adjacent peak-change crops generated; no automatic subjective PASS.')
