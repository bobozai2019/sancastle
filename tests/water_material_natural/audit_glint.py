"""Same-state solar term contribution, zero-gain negative and light-direction check."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'test_output/water_material_natural/t02_glint_sunward'
manifest=json.loads((out/'lighting_ablation.json').read_text())
result={'pass':False,'authority_identical':manifest['authority_identical'],'cameras':{}}
def read(case,debug,camera):
    entry=manifest['cases'][case]['images'][f'{debug}_{camera}']
    assert hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()==entry['sha256']
    return np.array(Image.open(entry['path'])).astype(float)
try:
    assert all(manifest['authority_identical'].values())
    board=Image.new('RGB',(1280,4*388),(25,29,33));draw=ImageDraw.Draw(board)
    for row,camera in enumerate(['oblique','close','grazing','sunward']):
        off,on,zero,yaw=[read(case,0,camera) for case in ['off','on','zero_gain','yaw180']]
        debug_off,debug_on,debug_zero,debug_yaw=[read(case,1,camera) for case in ['off','on','zero_gain','yaw180']]
        contribution=debug_on-debug_off
        result['cameras'][camera]={
            'zero_gain_equals_off_rgb':bool(np.array_equal(off,zero)),
            'debug_zero_equals_off_rgb':bool(np.array_equal(debug_zero,debug_off)),
            'solar_contribution_max_rgb_8bit':float(contribution.max()),
            'solar_changed_pixels':int((np.abs(contribution).max(2)>1).sum()),
            'sun_rotation_changes_solar_pixels':int((np.abs(debug_yaw-debug_on).max(2)>5).sum()),
            'production_glint_changed_pixels':int((np.abs(on-off).max(2)>1).sum())}
        assert result['cameras'][camera]['zero_gain_equals_off_rgb']
        assert result['cameras'][camera]['debug_zero_equals_off_rgb']
        assert result['cameras'][camera]['sun_rotation_changes_solar_pixels']>100
        for col,case in enumerate(['off','on']):
            entry=manifest['cases'][case]['images'][f'0_{camera}']
            board.paste(Image.open(entry['path']).resize((640,360)),(col*640,row*388+28))
            draw.text((col*640+8,row*388+8),camera+' / '+case,fill='white')
    assert result['cameras']['sunward']['solar_contribution_max_rgb_8bit']>50
    assert result['cameras']['sunward']['production_glint_changed_pixels']>1000
    board.save(out/'glint_board.png')
    result['pass']=True
    result['scope']='actual sun direction and half-vector solar contribution; manual route has no shadows'
except Exception as error:result['error']=repr(error)
(out/'audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
