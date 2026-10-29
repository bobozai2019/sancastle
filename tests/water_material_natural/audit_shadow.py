"""Verify actual shadow footprints on jointly visible water, excluding caster pixels."""
import json
from pathlib import Path
import hashlib
import numpy as np
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'test_output/water_material_natural/t02_shadow_v2'
manifest=json.loads((out/'shadow_ablation.json').read_text())
baseline=json.loads((ROOT/'test_output/water_material_natural/t00_baseline_v4/manifest.json').read_text())
captured=json.loads((out/'manifest.json').read_text())
result={'pass':False,'cameras':{},'authority_identical':manifest['authority_identical']}
def read(case,layer,debug,camera):
    key=f'{layer}_{debug}_{camera}'
    entry=manifest['cases'][case]['images'][key]
    assert hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()==entry['sha256']
    return np.array(Image.open(entry['path'])).astype(float)
try:
    assert all(manifest['authority_identical'].values())
    result['baseline_authority_identical']={f:baseline['fields'][f]['sha256']==captured['fields'][f]['sha256'] for f in baseline['fields']}
    assert all(result['baseline_authority_identical'].values())
    board=Image.new('RGB',(1280,3*388),(27,30,34));draw=ImageDraw.Draw(board)
    for row,camera in enumerate(['oblique','close','grazing']):
        on=read('shadow_on','water_only',2,camera)
        off=read('shadow_off','water_only',2,camera)
        hidden=read('caster_hidden','water_only',2,camera)
        # White mask is actual clear-light ATTENUATION output, not arbitrary dark pixels.
        mask=(off.min(2)>250)&(off.max(2)-off.min(2)<2)
        hidden_water=(hidden.max(2)-hidden.min(2)<2)&(hidden.min(2)>50)
        shared=mask&hidden_water
        shadow_pixels=mask&(on.mean(2)<200)&(on.max(2)-on.min(2)<3)
        restored=shadow_pixels&shared&(hidden.mean(2)-on.mean(2)>50)
        production_on=read('shadow_on','water_only',0,camera)
        production_off=read('shadow_off','water_only',0,camera)
        direct_on=read('direct_only','water_only',0,camera)
        all_off=read('all_off','water_only',0,camera)
        foam_on=read('shadow_on','foam_only',0,camera)
        foam_off=read('shadow_off','foam_only',0,camera)
        data={'clear_water_pixels':int(mask.sum()),'actual_shadow_pixels':int(shadow_pixels.sum()),
              'caster_removal_restores_pixels':int(restored.sum()),
              'shadow_production_rgb_mean_abs_8bit':float(np.abs(production_on-production_off)[shadow_pixels].mean()),
              'water_direct_term_mean_abs_8bit':float(np.abs(direct_on-all_off)[mask].mean()),
              'foam_only_shadow_changed_channels':int(np.count_nonzero(foam_on-foam_off)),
              'normal_debug_reference':'G1 macro+detail normal; engine input NORMAL is final n'}
        assert data['actual_shadow_pixels']>100 and data['caster_removal_restores_pixels']>100
        assert data['shadow_production_rgb_mean_abs_8bit']>.2
        assert data['water_direct_term_mean_abs_8bit']>.2
        assert data['foam_only_shadow_changed_channels']>0
        result['cameras'][camera]=data
        for col,case in enumerate(['shadow_off','shadow_on']):
            image=Image.open(manifest['cases'][case]['images'][f'combined_0_{camera}']['path']).resize((640,360))
            board.paste(image,(col*640,row*388+28));draw.text((col*640+8,row*388+8),camera+' / '+case,fill='white')
    board.save(out/'shadow_board.png')
    result['pass']=True
    result['scope']='same completed-state real directional shadow on water; independent foam render differences; not whole-scene similarity or cost gate'
except Exception as error:result['error']=repr(error)
(out/'audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
