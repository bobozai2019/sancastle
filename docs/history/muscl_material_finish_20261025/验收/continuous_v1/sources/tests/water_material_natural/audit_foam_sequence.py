import json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
out=Path(sys.argv[1]).resolve();d=json.loads((out/'foam_sequence.json').read_text())
r=json.loads((out/'process_result.json').read_text())
assert r['exit_code']==0 and r['engine_error_free'] and r['sources_unchanged_during_run']
assert len(d['frames'])==121 and all(p['unchanged'] and p['before']==p['after'] for p in d['authority_pairs'].values())
frames=[];rows=[];union=None;intersection=None
for i,f in enumerate(d['frames']):
    assert f['tick']==d['frames'][0]['tick']+3*i
    assert abs(f['time_s']-f['tick']/30)<1e-5
    a=Image.open(f['images']['all_on']['path']).convert('RGB')
    b=Image.open(f['images']['all_off']['path']).convert('RGB')
    delta=np.abs(np.asarray(a).astype(int)-np.asarray(b).astype(int)).max(2);mask=delta>5
    union=mask.copy() if union is None else union|mask
    intersection=mask.copy() if intersection is None else intersection&mask
    yy,xx=np.where(mask)
    rows.append({'tick':f['tick'],'time_s':f['time_s'],'coverage_px':int(mask.sum()),
        'centroid_px':[float(xx.mean()),float(yy.mean())] if len(xx) else None,
        'max_delta':int(delta.max())})
    board=Image.new('RGB',(1280,390),(20,20,20));draw=ImageDraw.Draw(board)
    board.paste(a.resize((640,360)),(0,30))
    diagnostics=Image.fromarray(np.uint8(np.minimum(delta*3,255))).convert('RGB').resize((640,360))
    board.paste(diagnostics,(640,30))
    draw.text((8,8),f"Completed tick {f['tick']} / {f['time_s']:.2f}s : full candidate",fill='white')
    draw.text((648,8),'Actual foam on/off RGB difference x3',fill='white')
    frames.append(board)
frames[0].save(out/'foam_sequence.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,optimize=False)
board=Image.new('RGB',(1280,780),(20,20,20))
for i,k in enumerate([0,30,60,120]):board.paste(frames[k].resize((640,390)),((i%2)*640,(i//2)*390))
board.save(out/'sequence_keyframes.png')
result={'frames':len(rows),'time_span_s':rows[-1]['time_s']-rows[0]['time_s'],
    'workload':d['workload'],'wave_request_count':d['wave_request_count'],'authority_pairs':d['authority_pairs'],
    'coverage_first':rows[0]['coverage_px'],'coverage_last':rows[-1]['coverage_px'],
    'coverage_min':min(x['coverage_px'] for x in rows),'coverage_max':max(x['coverage_px'] for x in rows),
    'union_px':int(union.sum()),'intersection_all_frames_px':int(intersection.sum()),'frames_metrics':rows,
    'limits':'12 simulated seconds at 10 fps, offline completed states. Contribution masks measure screen pixels, not particle lifetime, physical wave speed, realtime performance or final 60-second gate.'}
(out/'sequence_audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items() if k not in ['frames_metrics','authority_pairs']}))
