"""Alternative periodic texture: curved, uneven cells with broken borders."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/water_foam'
rng=np.random.default_rng(241025)
y,x=np.mgrid[:512,:512].astype(np.float32)/512
tau=np.pi*2
# Integer harmonics keep both axes periodic; warp before distance evaluation.
u=x+0.045*np.sin(tau*(2*y+x))+0.018*np.cos(tau*(5*y-3*x))
v=y+0.041*np.cos(tau*(2*x-y))+0.016*np.sin(tau*(4*x+3*y))
first=np.full_like(x,np.inf);second=first.copy()
for _ in range(46):
    cx,cy=rng.random(2)
    dx=(u-cx+0.5)%1-0.5;dy=(v-cy+0.5)%1-0.5
    distance=np.sqrt(dx*dx+dy*dy)*6
    second=np.minimum(second,np.maximum(first,distance));first=np.minimum(first,distance)
macro=0.5+0.25*np.sin(tau*(x+2*y)+1.7)+0.25*np.cos(tau*(3*x-y)+0.3)
fine=0.5+0.5*np.sin(tau*(11*x+7*y)+np.sin(tau*(3*x-4*y)))
width=0.12+0.16*macro
ridge=np.exp(-np.square((second-first)/width))
red=np.clip(0.12+ridge*(0.46+0.27*macro)*(0.62+0.38*fine),0,1)
rgba=np.stack([red,macro,np.zeros_like(red),np.ones_like(red)],axis=-1)
path=OUT/'foam_cells_organic.png'
Image.fromarray(np.uint8(np.rint(rgba*255))).save(path)
source='res://assets/water_foam/foam_cells_organic.png'
cache='res://.godot/imported/foam_cells_organic.png-'+hashlib.md5(source.encode()).hexdigest()+'.ctex'
old='res://assets/water_foam/foam_cells.png'
import_text=(OUT/'foam_cells.png.import').read_text(encoding='utf-8')
import re
import_text=re.sub(r'^uid=.*\n','',import_text,flags=re.M)
import_text=re.sub(r'res://\.godot/imported/foam_cells\.png-[a-f0-9]+\.ctex',cache,import_text).replace(old,source)
path.with_suffix('.png.import').write_text(import_text,encoding='utf-8')
(OUT/'organic_generation.json').write_text(json.dumps(dict(seed=241025,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),algorithm='Periodic domain-warped toroidal cells, uneven thickness and border breakup',size=[512,512],source='Self-generated; no external images'),indent=2),encoding='utf-8')
print(path)
