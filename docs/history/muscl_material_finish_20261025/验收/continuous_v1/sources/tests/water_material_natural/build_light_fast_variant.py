"""Test only the redundant standard specular mode; keep custom solar term identical."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
assets=ROOT/'assets/water_material_natural_candidate'
code=(assets/'water_engine_light.gdshader').read_text()
code=code.replace('render_mode ambient_light_disabled,','render_mode specular_disabled, ambient_light_disabled,')
(assets/'water_engine_light_no_standard_specular.gdshader').write_text(code,encoding='utf-8')
print('Built standard-specular-disabled experiment; custom light term preserved in source')
