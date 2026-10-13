from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[2]
a=ROOT/'assets/water_material_natural_candidate';s=ROOT/'scenes/water_material_natural_candidate'
shader='res://assets/water_material_natural_candidate/water_optics_unrefracted.gdshader'
code=(a/'water_path_diagnostic.gdshader').read_text().replace('// Diagnostic only; not a published composition-profile field.','// Optics schema2 separates the unbent camera-ray path from guarded color offset.')
(a/'water_optics_unrefracted.gdshader').write_text(code,encoding='utf-8')
base=json.loads((a/'base_v8_optics.json').read_text());base['resources']['water_shader']=shader
(a/'base_v8_optics_unrefracted.json').write_text(json.dumps(base,indent=2),encoding='utf-8')
lighting=json.loads((a/'lighting_optics.json').read_text());lighting.update(base_profile='res://assets/water_material_natural_candidate/base_v8_optics_unrefracted.json',water_shader=shader)
(a/'lighting_optics_unrefracted.json').write_text(json.dumps(lighting,indent=2),encoding='utf-8')
profile=json.loads((a/'optics_reconstructed.json').read_text())
profile.update(optics_schema_version=2,path_mode='depth_unrefracted',lighting_profile='res://assets/water_material_natural_candidate/lighting_optics_unrefracted.json',lighting_profile_sha256=hashlib.sha256((a/'lighting_optics_unrefracted.json').read_bytes()).hexdigest())
(a/'optics_unrefracted.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
(s/'optics_unrefracted.tscn').write_text((s/'optics_reconstructed.tscn').read_text().replace('optics_reconstructed.json','optics_unrefracted.json'),encoding='utf-8')
