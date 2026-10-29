import json,re,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];a=ROOT/'assets/water_material_natural_candidate';s=ROOT/'scenes/water_material_natural_candidate'
source=ROOT/'assets/test1_beach/test1_bed_lit_fast.gdshader';old=source.read_text()
header='''uniform bool natural_caustic_override = false;
uniform bool natural_caustic_enabled = true;
uniform float natural_caustic_strength = 0.8;
uniform float natural_caustic_softness = 1.0;
uniform float natural_caustic_uv_scale = 2.0;
'''
code=old.replace('uniform sampler2D rock_state',header+'uniform sampler2D rock_state',1)
code=code.replace('if (debug_mode == 0 && phase2_caustics) {','if (debug_mode == 0 && phase2_caustics && (!natural_caustic_override || natural_caustic_enabled)) {',1)
for field in ['strength','softness','uv_scale']:
    code='\n'.join(line if line.lstrip().startswith('uniform ') else re.sub(
        r'\bprototype_caustic_'+field+r'\b',f'(natural_caustic_override ? natural_caustic_{field} : prototype_caustic_{field})',line)
        for line in code.split('\n'))
(a/'bed_style.gdshader').write_text(code,encoding='utf-8')
def geometry(text):
    prefix=text.split('void fragment()',1)[0]
    return '\n'.join(line for line in prefix.splitlines() if not line.startswith('uniform bool natural_') and not line.startswith('uniform float natural_'))
assert geometry(old)==geometry(code)
report={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'candidate':str(a/'bed_style.gdshader'),'candidate_sha256':hashlib.sha256((a/'bed_style.gdshader').read_bytes()).hexdigest(),
    'geometry_prefix_unchanged':True,'geometry_prefix_sha256':hashlib.sha256(geometry(old).encode()).hexdigest()}
(a/'bed_style_generation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
base=json.loads((a/'base_v8_reflection.json').read_text())
for key in ['terrain_fixed_shader','terrain_coupled_shader']:base['resources'][key]='res://assets/water_material_natural_candidate/bed_style.gdshader'
(a/'base_v8_style.json').write_text(json.dumps(base,indent=2),encoding='utf-8')
p={'style_schema_version':1,'reflection_profile':'res://assets/water_material_natural_candidate/reflection_oriented.json',
    'reflection_profile_sha256':hashlib.sha256((a/'reflection_oriented.json').read_bytes()).hexdigest(),
    'base_profile':'res://assets/water_material_natural_candidate/base_v8_style.json',
    'bed_shader':base['resources']['terrain_fixed_shader'],'bed_shader_sha256':report['candidate_sha256'],
    'source_bed_shader':'res://assets/test1_beach/test1_bed_lit_fast.gdshader','source_bed_shader_sha256':report['source_sha256'],
    'caustics':{'enabled':True,'strength':.8,'softness':1.,'uv_scale':2.},
    'glint':{'gain':.32,'exponent':42.},'detail_gain_multiplier':1.}
scene=(s/'reflection_oriented.tscn').read_text().replace('reflection_entry.gd','style_entry.gd').replace(
    'reflection_profile_path = "res://assets/water_material_natural_candidate/reflection_oriented.json"',
    'style_profile_path = "res://assets/water_material_natural_candidate/style_baseline.json"')
(a/'style_baseline.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
(s/'style_baseline.tscn').write_text(scene,encoding='utf-8')
p['caustics'].update(softness=.5,uv_scale=3.);p['glint']['gain']=.96;p['detail_gain_multiplier']=8.
(a/'style_combination.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
(s/'style_combination.tscn').write_text(scene.replace('style_baseline.json','style_combination.json'),encoding='utf-8')
print(json.dumps(report))
