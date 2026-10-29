"""Reduce fragment-to-light live data without removing any active visual feature."""
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
assets=ROOT/'assets/water_material_natural_candidate'
scenes=ROOT/'scenes/water_material_natural_candidate'
code=(assets/'water_engine_light.gdshader').read_text()
code=code.replace('varying vec3 natural_scatter_layer;\nvarying vec3 natural_foam_layer;\nvarying float natural_glint_depth_gate;',
                  'varying vec2 natural_optical_weights;\nvarying float natural_water_depth;')
code=code.replace('    natural_scatter_layer = vec3(0.0);\n    natural_foam_layer = vec3(0.0);\n    natural_glint_depth_gate = 0.0;',
                  '    natural_optical_weights = vec2(0.0);\n    natural_water_depth = 0.0;')
code=code.replace('        natural_glint_depth_gate = smoothstep(0.008, 0.05, depth);','        natural_water_depth = depth;')
code=code.replace('''            natural_scatter_layer = scatter * (1.0 - transmission) *
                (1.0 - preserved_bed) * (1.0 - reflect_weight);''',
'''            natural_optical_weights.x = (1.0 - transmission) *
                (1.0 - preserved_bed) * (1.0 - reflect_weight);''')
code=code.replace('            natural_scatter_layer *= 1.0 - white_fraction;\n            natural_foam_layer = foam_tint * white_fraction;',
                  '            natural_optical_weights.x *= 1.0 - white_fraction;\n            natural_optical_weights.y = white_fraction;')
code=code.replace('''    vec3 direct_layer = natural_scatter_layer * natural_scatter_direct_fraction +
        natural_foam_layer * natural_foam_direct_fraction;''',
'''    vec3 direct_layer = natural_scatter_color(natural_water_depth) * natural_optical_weights.x * natural_scatter_direct_fraction +
        foam_tint * natural_optical_weights.y * natural_foam_direct_fraction;''')
code=code.replace('''        natural_scatter_layer = vec3(0.0);
        natural_foam_layer = vec3(0.0);
        natural_glint_depth_gate = 0.0;''','''        natural_optical_weights = vec2(0.0);
        natural_water_depth = 0.0;''')
code=code.replace('void fragment() {','''vec3 natural_scatter_color(float depth) {
    return mix(phase2_shallow_tint, phase2_deep_tint, smoothstep(0.02, 0.30, depth)) *
        mix(1.0, prototype_screen_deep_scatter_scale, smoothstep(0.08, 0.20, depth));
}

void fragment() {''')
code=code.replace('''        vec3 direct = (natural_scatter_layer * natural_scatter_direct_fraction +
            natural_foam_layer * natural_foam_direct_fraction) *''','''        vec3 scatter_layer = natural_scatter_color(natural_water_depth) * natural_optical_weights.x;
        vec3 foam_layer = foam_tint * natural_optical_weights.y;
        vec3 direct = (scatter_layer * natural_scatter_direct_fraction +
            foam_layer * natural_foam_direct_fraction) *''')
code=code.replace('natural_glint_gain * natural_glint_depth_gate : 0.0;',
                  'natural_glint_gain * smoothstep(0.008, 0.05, natural_water_depth) : 0.0;')
code=code.replace('DIFFUSE_LIGHT += natural_scatter_layer *','DIFFUSE_LIGHT += scatter_layer *')
code=code.replace('DIFFUSE_LIGHT += natural_foam_layer *','DIFFUSE_LIGHT += foam_layer *')
assert 'natural_scatter_layer' not in code and 'natural_glint_depth_gate' not in code
(assets/'water_engine_light_packed.gdshader').write_text(code,encoding='utf-8')
# Only legacy experiment/debug switches are frozen. Active field/capability switches are untouched.
snapshot=json.loads((ROOT/'test_output/water_material_natural/t02_shadow_layers/manifest.json').read_text())['water_uniforms']
frozen=[name for name,value in snapshot.items() if value is False and
        (name.endswith('_debug') or name in ['prototype_geometry_silhouette','prototype_screen_scene_reflection','prototype_screen_sky_gradient','prototype_screen_bed_only'])]
specialized=code
for name in frozen:
    pattern=re.compile(r'\b'+re.escape(name)+r'\b')
    specialized='\n'.join(line if line.lstrip().startswith('uniform ') else pattern.sub('false',line) for line in specialized.split('\n'))
(assets/'water_engine_light_specialized.gdshader').write_text(specialized,encoding='utf-8')
base=json.loads((ROOT/'assets/test1_beach/test1_beach_release.json').read_text())
base['resources']['water_shader']='res://assets/water_material_natural_candidate/water_engine_light_packed.gdshader'
(assets/'base_v8_engine_packed.json').write_text(json.dumps(base,indent=2),encoding='utf-8')
profile=json.loads((assets/'lighting_engine.json').read_text())
profile.update(water_shader=base['resources']['water_shader'],base_profile='res://assets/water_material_natural_candidate/base_v8_engine_packed.json')
(assets/'lighting_packed.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
scene=(scenes/'lighting_engine.tscn').read_text().replace('lighting_engine.json','lighting_packed.json')
(scenes/'lighting_packed.tscn').write_text(scene,encoding='utf-8')
(ROOT/'test_output/water_material_natural/t02_packed_build.json').write_text(json.dumps({'fragment_to_light_floats_before':7,'after':3,'specialized_legacy_false_flags':frozen,'active_capabilities':'unchanged','adopted':False},indent=2))
print('Packed 7 to 3 float light inputs; equivalence and benefit pending')
