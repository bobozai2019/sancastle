import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

out = Path(sys.argv[1]).resolve()
d = json.loads((out/'foam_factors.json').read_text())
run = json.loads((out/'process_result.json').read_text())
assert run['exit_code'] == 0 and run['engine_error_free'] and run['sources_unchanged_during_run']
assert all(d['fields_unchanged'].values())
load = lambda case, mode, cam: np.asarray(Image.open(d['cases'][case]['images'][f'{mode}_{cam}']['path']).convert('RGB')).astype(int)
rows = {}
for cam in ['oblique','close','grazing']:
    rows[cam] = {}
    old = np.asarray(Image.open(out.parent/'t04_contact_shared_v3'/f'all_on_{cam}.png').convert('RGB')).astype(int)
    assert np.abs(old-load('baseline','production',cam)).max() == 0
    for mode in ['production','fine_only']:
        board = Image.new('RGB',(1920,620),(24,24,24))
        draw = ImageDraw.Draw(board)
        for i,case in enumerate(d['cases']):
            a=load(case,mode,cam);x=i%4*480;y=i//4*310
            board.paste(Image.fromarray(a.astype(np.uint8)).resize((480,270)),(x,y+25))
            draw.text((x+5,y+5),f'{case} {mode} {cam}',fill='white')
            delta=np.abs(a-load('baseline',mode,cam)).max(2)
            rows[cam][f'{case}_{mode}']={'changed_pixels_over_one_bit':int((delta>1).sum()),'max_delta':int(delta.max())}
        board.save(out/f'factors_{mode}_{cam}.png')

# Diagram from actual ArrayMesh UV centers and the selected shader's local-dense
# mapping. Candidate slots are not live particles. Shader hash jitter remains
# GPU computed; this diagram intentionally plots pre-jitter centers.
uv=np.asarray(d['mesh']['centers_uv'])
u=d['mesh']['fine_uniforms']
assert u['front_local_dense'] and not u['front_concentrated']
x=(64+uv[:,0]*128+.5)*.125-16
z=uv[:,1]*32-16
board=Image.new('RGB',(1100,650),(24,24,24));draw=ImageDraw.Draw(board)
draw.text((20,15),'8192 static candidate slots: actual mesh UV -> shader world XZ; pre-jitter',fill='white')
for a,b in zip(x,z):
    px=40+(a+16)/32*560;py=60+(b+16)/32*560
    draw.ellipse((px-1,py-1,px+1,py+1),fill=(85,170,225))
draw.rectangle((40,60,600,620),outline='white')
draw.text((635,65),'Local-dense X envelope:',fill='white')
draw.text((635,90),f'X {x.min():.3f}..{x.max():.3f} m',fill='white')
draw.text((635,115),f'Z {z.min():.3f}..{z.max():.3f} m',fill='white')
draw.text((635,150),'64 columns x 128 rows; spacing 0.25 m',fill='white')
draw.text((635,180),'Baseline stable hash jitter +/-0.02 m',fill='white')
draw.text((635,210),'Front field, foam, wet depth select coverage.',fill='white')
draw.text((635,240),'8192 slots does not mean 8192 visible splats.',fill='white')
draw.text((635,270),'No runtime births or new visual history.',fill='white')
board.save(out/'candidate_slots.png')
result={'baseline_equivalent':True,'fields_unchanged':d['fields_unchanged'],'cameras':rows,
    'slot_distribution':{'count':len(uv),'unique_uv':len(np.unique(uv,axis=0)),'x_range_m':[float(x.min()),float(x.max())],
    'z_range_m':[float(z.min()),float(z.max())],'mesh_sha256':d['mesh']['sha256'],'diagram_scope':'Pre-jitter static candidates, not actual active foam or GPU hash validation'},
    'scope':'Single fixed completed state; does not prove temporal lifecycle, dry negatives, visual improvement or performance.'}
(out/'factor_audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
