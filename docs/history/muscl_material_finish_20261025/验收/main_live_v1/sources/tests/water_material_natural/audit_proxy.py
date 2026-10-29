"""Use the frozen 2px edge criterion; do not accept interior leaks for cost benefit."""
import hashlib
import json
from pathlib import Path
from PIL import Image,ImageFilter,ImageDraw
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'test_output/water_material_natural/t02_proxy_shadow'
manifest=json.loads((out/'proxy_ablation.json').read_text())
result={'pass':False,'cameras':{},'criterion':'8bit attenuation difference >20 must lie within 2px of either shadow boundary'}
def read(case,debug,camera):
    entry=manifest['cases'][case]['images'][f'{debug}_{camera}']
    assert hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()==entry['sha256']
    return np.array(Image.open(entry['path'])).astype(float)
def dilate(a,size):return np.array(Image.fromarray((a*255).astype('uint8')).filter(ImageFilter.MaxFilter(size)))>0
def erode(a,size):return np.array(Image.fromarray((a*255).astype('uint8')).filter(ImageFilter.MinFilter(size)))>0
try:
    process=json.loads((out/'process_result.json').read_text())
    assert process['exit_code']==0 and process['sources_unchanged_during_run']
    board=Image.new('RGB',(1280,4*388),(25,29,33));draw=ImageDraw.Draw(board)
    for row,camera in enumerate(['oblique','close','grazing','sunward']):
        n,p=read('native',2,camera),read('proxy',2,camera)
        mask=(n.max(2)-n.min(2)<2)&(p.max(2)-p.min(2)<2)
        ns=mask&(n.mean(2)<200);ps=mask&(p.mean(2)<200)
        edge=(ns^erode(ns,3))|(ps^erode(ps,3))
        significant=mask&(np.abs(n-p).max(2)>20)
        outside=significant&~dilate(edge,5)
        data={'shared_gray_water_pixels':int(mask.sum()),'significant_difference_pixels':int(significant.sum()),
              'outside_2px_boundary_pixels':int(outside.sum()),
              'water_mean_abs_attenuation_8bit':float(np.abs(n-p)[mask].mean())}
        result['cameras'][camera]=data
        for col,case in enumerate(['native','proxy']):
            entry=manifest['cases'][case]['images'][f'2_{camera}']
            board.paste(Image.open(entry['path']).resize((640,360)),(col*640,row*388+28))
            draw.text((col*640+8,row*388+8),camera+' / '+case,fill='white')
    board.save(out/'proxy_board.png')
    assert all(c['outside_2px_boundary_pixels']==0 for c in result['cameras'].values()),'interior shadow differences outside frozen tolerance'
    result['pass']=True
except Exception as error:result['error']=repr(error)
(out/'audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
