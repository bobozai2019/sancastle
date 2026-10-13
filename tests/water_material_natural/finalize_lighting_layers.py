"""Combine scoped fine-foam evidence with retained insufficient grazing result."""
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'test_output/water_material_natural/t02_shadow_layers'
manifest=json.loads((out/'shadow_ablation.json').read_text())
result={'pass':False,'cameras':{},'authority_identical':manifest['authority_identical'],
        'original_grazing_probe':'FAIL retained: 4 shadowed core pixels below >5 diagnostic criterion',
        'grazing_followup':json.loads((ROOT/'test_output/water_material_natural/t02_grazing_foam_shadow/audit.json').read_text())}
def read(case,layer,debug,camera):
    return np.array(Image.open(manifest['cases'][case]['images'][f'{layer}_{debug}_{camera}']['path'])).astype(float)
try:
    assert all(result['authority_identical'].values())
    for camera in ['oblique','close','grazing','sunward']:
        off,on,hidden,background=[read(c,l,d,camera) for c,l,d in [('shadow_off','foam_only',2),('shadow_on','foam_only',2),('caster_hidden','foam_only',2),('shadow_off','fine_hidden',0)]]
        core=(off.min(2)>250)&(off.max(2)-off.min(2)<2)&(np.abs(off-background).max(2)>20)
        shadow=core&(on.max(2)-on.min(2)<3)&(on.mean(2)<200)
        restored=shadow&(hidden.mean(2)-on.mean(2)>50)
        base=read('all_off','water_only',0,camera)
        scatter=read('scatter_only','water_only',0,camera)
        foam=read('foam_only','water_only',0,camera)
        result['cameras'][camera]={'core_pixels':int(core.sum()),'shadow_pixels':int(shadow.sum()),
                                  'restored_pixels':int(restored.sum()),
                                  'scatter_fraction_alone_changes_pixels':int((np.abs(scatter-base).max(2)>1).sum()),
                                  'main_foam_fraction_alone_changes_pixels':int((np.abs(foam-base).max(2)>1).sum())}
        if camera!='grazing':assert shadow.sum()>5 and restored.sum()>5
        assert result['cameras'][camera]['scatter_fraction_alone_changes_pixels']>1000
        assert result['cameras'][camera]['main_foam_fraction_alone_changes_pixels']>100
    assert result['grazing_followup']['pass']
    result['pass']=True
    result['conclusion']='real directional shadow modulates drawn fine-foam cores; separate scatter and main-foam fractions consumed; no whole-image shadow attribution'
except Exception as error:result['error']=repr(error)
(out/'final_layer_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
