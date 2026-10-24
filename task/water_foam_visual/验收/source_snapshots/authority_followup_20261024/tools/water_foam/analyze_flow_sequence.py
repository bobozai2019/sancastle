"""Track local screen motion and phase-boundary differences in actual captures."""
import argparse
import json
import re
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--run-id',default='flow_fixture_v1')
args=parser.parse_args()
RUN=ROOT/'task/water_foam_visual/验收/G2'/args.run_id

def load(path):
    return np.asarray(Image.open(path).convert('RGB'),dtype=np.float32)

def motion(a,b,roi):
    x,y,w,h=roi
    patch=a[y:y+h,x:x+w]
    gray=patch.mean(2)
    valid=np.ptp(patch,axis=2)<3
    best=None
    for dy in range(-6,7):
        for dx in range(-6,7):
            target=b[y+dy:y+dy+h,x+dx:x+dx+w]
            mask=valid&(np.ptp(target,axis=2)<3)
            if mask.sum()<200:continue
            score=float(np.mean((gray[mask]-target.mean(2)[mask])**2))
            if best is None or score<best['mse']:best=dict(dx=dx,dy=dy,mse=score,pixels=int(mask.sum()))
    return best

results={}
for scene in ['main','test1_geometry']:
    directory=RUN/scene
    probe=directory/'probe.json'
    if not probe.exists():continue
    data=json.loads(probe.read_text(encoding='utf-8-sig'))
    fixture=data['observations']['flow_fixture']
    expected=np.array([float(v) for v in re.findall(r'-?\d+(?:\.\d+)?',fixture['screen_world_x'].split('(')[1])][:2])
    roi=[160,430,230,110] if scene=='main' else [800,390,170,100]
    row=dict(roi=roi,screen_world_x=expected.tolist(),probe_pass=data['pass'],fixtures={})
    for name in ['positive','negative']:
        records=[f for f in fixture['frames'] if f['fixture']==name]
        frames=[load(directory/f['file']) for f in records]
        x,y,w,h=roi
        crop=[a[y:y+h,x:x+w].mean(2) for a in frames]
        delta=[float(np.mean(np.abs(b-a))/255) for a,b in zip(crop,crop[1:])]
        track=motion(frames[0],frames[2],roi)
        direction=expected*(1 if name=='positive' else -1)
        vector=np.array([track['dx'],track['dy']])
        cosine=float(np.dot(direction,vector)/max(np.linalg.norm(direction)*np.linalg.norm(vector),1e-9))
        boundaries={str(records[i]['time_s']):max(delta[i-1],delta[i]) for i in range(1,len(records)-1) if abs(records[i]['time_s']%2)<1e-5}
        p95=float(np.percentile(delta,95))
        row['fixtures'][name]=dict(frames=len(frames),time_s=[records[0]['time_s'],records[-1]['time_s']],local_motion_0_to_02_s=track,projected_direction_cosine=cosine,mean_abs_step=float(np.mean(delta)),p95_abs_step=p95,boundary_abs_step=boundaries,boundary_to_p95_ratio={k:v/max(p95,1e-9) for k,v in boundaries.items()},note='Motion is local integer-pixel matching on grayscale water mask; phase blending need not preserve every individual bubble.')
    results[scene]=row
(RUN/'motion_analysis.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(results,ensure_ascii=False,indent=2))
