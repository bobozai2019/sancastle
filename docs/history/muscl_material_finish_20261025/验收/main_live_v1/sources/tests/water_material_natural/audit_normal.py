"""Check normal mode contribution, authority isolation and retain an A/B board."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'test_output/water_material_natural/t01_ablation'
manifest=json.loads((out/'normal_ablation.json').read_text())
baseline=json.loads((ROOT/'test_output/water_material_natural/t00_baseline_v4/manifest.json').read_text())
candidate=json.loads((out/'manifest.json').read_text())
audit=json.loads((ROOT/'test_output/water_material_natural/t00_audit.json').read_text())
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
result={'pass':False,'authority_identical':manifest['authority_identical'],'comparisons':{},
        'unknowns':['Exact original UV/decode/time formula remains unknown.',
                    'Static mode contribution does not prove lifecycle or temporal stability.',
                    'Remaining broad cyan appearance is outside normal-only attribution.']}
try:
    assert all(manifest['authority_identical'].values())
    result['baseline_authority_identical']={f:baseline['fields'][f]['sha256']==candidate['fields'][f]['sha256'] for f in baseline['fields']}
    assert all(result['baseline_authority_identical'].values())
    result['formal_sources_unchanged']=all(sha(p['path'])==p['sha256'] for p in audit['protected_sources'])
    assert result['formal_sources_unchanged']
    rois={'oblique':{'shallow':[450,420,155,80],'deep':[285,500,160,110],'contact':[755,495,110,120],'front':[655,315,120,95]},
          'close':{'shallow':[30,580,215,110],'deep':[250,495,190,80],'contact':[845,545,135,110],'front':[510,337,155,60]},
          'grazing':{'shallow':[850,625,240,85],'deep':[330,550,270,70],'contact':[900,405,260,95],'front':[665,380,235,80]}}
    for camera in rois:
        arrays={m:np.array(Image.open(out/f'mode{m}_debug0_{camera}.png')).astype(float) for m in range(3)}
        result['comparisons'][camera]={}
        for name,(x,y,w,h) in rois[camera].items():
            crops={m:a[y:y+h,x:x+w] for m,a in arrays.items()}
            result['comparisons'][camera][name]={f'{a}_vs_{b}_mean_abs_8bit':float(np.abs(crops[a]-crops[b]).mean()) for a,b in [(0,1),(0,2),(1,2)]}
        assert result['comparisons'][camera]['deep']['0_vs_2_mean_abs_8bit'] > .02
        for debug in range(3):
            for m in range(3):
                entry=manifest['cases'][str(m)]['images'][str(debug)][camera]
                assert sha(entry['path'])==entry['sha256']
        # Inside confirmed visible deep-water ROI, off detail must be neutral.
        x,y,w,h=rois[camera]['deep']
        result['comparisons'][camera]['detail_debug_std']={str(m):np.array(Image.open(out/f'mode{m}_debug2_{camera}.png'))[y:y+h,x:x+w].std((0,1)).tolist() for m in range(3)}
    board=Image.new('RGB',(1280,3*400+3*28),(25,28,33));draw=ImageDraw.Draw(board)
    for row,camera in enumerate(['oblique','close','grazing']):
        for col,m in enumerate([1,2]):
            image=Image.open(out/f'mode{m}_debug0_{camera}.png').resize((640,360))
            y=row*428
            board.paste(image,(col*640,y+28))
            draw.text((col*640+12,y+8),camera+' / '+('legacy sine' if m==1 else 'texture layers'),fill='white')
    board.save(out/'comparison_board.png')
    result['board']={'path':str(out/'comparison_board.png'),'sha256':sha(out/'comparison_board.png')}
    result['candidate_resources']=[{'path':str(p),'sha256':sha(p)} for p in (ROOT/'assets/water_material_natural_candidate').iterdir() if p.is_file() and not p.name.endswith('.uid')]
    result['pass']=True
except Exception as error:result['error']=repr(error)
(out/'audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'pass':result['pass'],'error':result.get('error'),'comparisons':result['comparisons']}))
