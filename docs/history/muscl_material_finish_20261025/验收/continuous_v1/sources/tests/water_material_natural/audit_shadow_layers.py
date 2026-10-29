"""Reject whole-image darkening evidence; identify actual fine-foam core draw pixels."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'test_output/water_material_natural/t02_shadow_layers'
manifest=json.loads((out/'shadow_ablation.json').read_text())
result={'pass':False,'cameras':{},'authority_identical':manifest['authority_identical']}
def read(case,layer,debug,camera):
    entry=manifest['cases'][case]['images'][f'{layer}_{debug}_{camera}']
    assert hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()==entry['sha256']
    return np.array(Image.open(entry['path'])).astype(float)
try:
    assert all(manifest['authority_identical'].values())
    assert json.loads((out/'process_result.json').read_text())['sources_unchanged_during_run']
    for camera in ['oblique','close','grazing','sunward']:
        off=read('shadow_off','foam_only',2,camera)
        on=read('shadow_on','foam_only',2,camera)
        hidden=read('caster_hidden','foam_only',2,camera)
        no_fine=read('shadow_off','fine_hidden',0,camera)
        fine_core=(off.min(2)>250)&(off.max(2)-off.min(2)<2)&(np.abs(off-no_fine).max(2)>20)
        shadowed=fine_core&(on.max(2)-on.min(2)<3)&(on.mean(2)<200)
        restored=shadowed&(hidden.mean(2)-on.mean(2)>50)
        base=read('all_off','water_only',0,camera)
        scatter=read('scatter_only','water_only',0,camera)
        foam=read('foam_only','water_only',0,camera)
        data={'fine_core_pixels':int(fine_core.sum()),'shadowed_fine_pixels':int(shadowed.sum()),
              'caster_removal_restores_fine_pixels':int(restored.sum()),
              'scatter_only_changed_pixels':int((np.abs(scatter-base).max(2)>1).sum()),
              'main_foam_only_changed_pixels':int((np.abs(foam-base).max(2)>1).sum()),
              'scoped_mask':'opaque debug core ALPHA>=0.05; clear attenuation white and differs from identical hidden-fine background'}
        assert data['fine_core_pixels']>100
        assert data['shadowed_fine_pixels']>5
        assert data['caster_removal_restores_fine_pixels']>5
        assert data['scatter_only_changed_pixels']>1000
        assert data['main_foam_only_changed_pixels']>100
        result['cameras'][camera]=data
    result['pass']=True
    result['scope']='actual fine-foam draw core and shadow/caster negative; main foam and scatter fractions each isolated; production alpha/geometry unchanged'
except Exception as error:result['error']=repr(error)
(out/'audit_layers.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
