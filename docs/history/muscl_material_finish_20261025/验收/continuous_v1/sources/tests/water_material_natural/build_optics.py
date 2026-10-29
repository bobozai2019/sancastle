"""Create a path-only candidate from the selected native lighting shader."""
from pathlib import Path
import json,hashlib,re
ROOT=Path(__file__).resolve().parents[2]
a=ROOT/'assets/water_material_natural_candidate'
s=ROOT/'scenes/water_material_natural_candidate'
code=(a/'water_engine_light.gdshader').read_text()
code=code.replace('void fragment() {','''uniform int natural_path_mode = 0;
uniform int natural_optics_debug = 0;
uniform float natural_scatter_gain = 1.0;

void fragment() {''')
old='''        float path_length = depth / max(abs(dot(normalize(VIEW), n)), 0.25);'''
new='''        float path_length = depth / max(abs(dot(normalize(VIEW), n)), 0.25);
        float sampled_depth = textureLod(prototype_scene_depth, sampled_uv, 0.0).r;
        vec4 sampled_view_h = INV_PROJECTION_MATRIX * vec4(sampled_uv * 2.0 - 1.0, sampled_depth, 1.0);
        vec3 sampled_view = sampled_view_h.xyz / max(abs(sampled_view_h.w), 0.000001) * sign(sampled_view_h.w);
        float reconstructed_path = length(sampled_view - VERTEX);
        bool invalid_path = sampled_depth <= 0.000001 || abs(sampled_view_h.w) <= 0.000001 ||
            -sampled_view.z <= surface_distance + 0.005 || reconstructed_path > 50.0;
        if (natural_path_mode == 1 && !invalid_path) {
            path_length = reconstructed_path;
        }'''
assert old in code
code=code.replace(old,new)
code=code.replace('''        vec3 transmitted = bed_color * transmission''','''        scatter *= natural_scatter_gain;
        vec3 transmitted = bed_color * transmission''')
# Debug overrides all composited water terms, then disable direct lighting below.
anchor='''        if (prototype_refraction_fallback_debug) {'''
pos=code.index(anchor)
code=code[:pos]+'''        if (natural_optics_debug == 1) {
            ALBEDO = depth < 0.02 ? vec3(0.0) : (depth < 0.08 ? vec3(1.0,0.0,0.0) :
                (depth < 0.20 ? vec3(0.0,1.0,0.0) : vec3(0.0,0.0,1.0)));
        } else if (natural_optics_debug == 2) {
            ALBEDO = vec3(clamp(path_length,0.0,1.0));
        } else if (natural_optics_debug == 3) {
            ALBEDO = vec3(blocked_by_depth ? 1.0 : 0.0, outside_screen ? 1.0 : 0.0, invalid_path ? 1.0 : 0.0);
        } else if (natural_optics_debug == 4) {
            ALBEDO = vec3(transmission);
        } else if (natural_optics_debug == 5) {
            ALBEDO = scatter;
        } else if (natural_optics_debug == 6) {
            ALBEDO = bed_color;
        }
''' +code[pos:]
code=code.replace('''    vec3 direct_layer = natural_scatter_layer''','''    if (natural_optics_debug > 0) {
        natural_scatter_layer = vec3(0.0);
        natural_foam_layer = vec3(0.0);
        natural_glint_depth_gate = 0.0;
        ALPHA = 1.0;
    }
    vec3 direct_layer = natural_scatter_layer''')
(a/'water_optics.gdshader').write_text(code,encoding='utf-8')
base=json.loads((ROOT/'assets/test1_beach/test1_beach_release.json').read_text())
base['resources']['water_shader']='res://assets/water_material_natural_candidate/water_optics.gdshader'
(a/'base_v8_optics.json').write_text(json.dumps(base,indent=2),encoding='utf-8')
lighting=json.loads((a/'lighting_engine.json').read_text())
lighting.update(base_profile='res://assets/water_material_natural_candidate/base_v8_optics.json',water_shader=base['resources']['water_shader'])
(a/'lighting_optics.json').write_text(json.dumps(lighting,indent=2),encoding='utf-8')
actual=json.loads((ROOT/'test_output/water_material_natural/t02_shadow_layers/manifest.json').read_text())['water_uniforms']
origins={}
def effective_float(name):
    value=actual[name]
    if isinstance(value,(int,float)) and not isinstance(value,bool):
        origins[name]={'source':'explicit material binding','value':value}
        return value
    default=re.search(r'uniform float '+re.escape(name)+r' = ([0-9.]+);',code)
    assert default, name
    value=float(default.group(1))
    origins[name]={'source':'shader default; material snapshot was unset','value':value}
    return value
profile={'optics_schema_version':1,'lighting_profile':'res://assets/water_material_natural_candidate/lighting_optics.json',
    'lighting_profile_sha256':hashlib.sha256((a/'lighting_optics.json').read_bytes()).hexdigest(),
    'path_mode':'legacy_vertical','extinction_shallow_m':effective_float('prototype_shallow_extinction_m'),
    'extinction_deep_m':effective_float('prototype_deep_extinction_m'),'scatter_gain':1.0,
    'shallow_preserve':actual['prototype_optical_shallow_preserve'],'refraction_scale':actual['prototype_refraction_scale']}
(a/'optics_legacy.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
profile['path_mode']='depth_reconstructed'
(a/'optics_reconstructed.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
scene=(s/'lighting_engine.tscn').read_text().replace('lighting_entry.gd','optics_entry.gd').replace(
    'lighting_profile_path = "res://assets/water_material_natural_candidate/lighting_engine.json"',
    'optics_profile_path = "res://assets/water_material_natural_candidate/optics_legacy.json"')
(s/'optics_legacy.tscn').write_text(scene,encoding='utf-8')
(s/'optics_reconstructed.tscn').write_text(scene.replace('optics_legacy.json','optics_reconstructed.json'),encoding='utf-8')
(ROOT/'test_output/water_material_natural/t03_parameter_origins.json').write_text(json.dumps(origins,indent=2))
print(json.dumps(profile))
