import re,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];a=ROOT/'assets/water_material_natural_candidate';s=ROOT/'scenes/water_material_natural_candidate'
code=(a/'water_foam.gdshader').read_text()
code=code.replace('uniform float natural_main_foam_gain','''uniform bool natural_reflection_protected = false;
uniform bool natural_reflection_perturbation = false;
uniform float natural_reflection_gain = 1.0;
uniform sampler2D natural_planar_reflection_srgb : source_color, filter_linear, repeat_disable;
uniform bool natural_reflection_srgb = false;
uniform bool natural_reflection_flip_y = false;
uniform vec3 natural_reflection_sky_linear = vec3(0.55,0.75,0.86);
uniform float natural_reflection_shift_m = 0.25;
uniform float natural_reflection_uv_limit = 0.03;
uniform float natural_reflection_edge_margin_px = 2.0;
uniform float natural_reflection_edge_fade_px = 8.0;
uniform int natural_reflection_debug = 0;
uniform float natural_main_foam_gain''',1)
code=code.replace('void fragment() {','void fragment() {\n    vec3 natural_reflection_diag_color=vec3(0.0);',1)
code=code.replace('            vec2 reflected_uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y);',
'''            float planar_w=1.0;
            vec2 reflected_uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y);''',1)
code=code.replace('                reflected_uv = reflected_clip.xy / reflected_clip.w * 0.5 + 0.5;',
'''                planar_w=reflected_clip.w;
                reflected_uv = reflected_clip.xy / reflected_clip.w * 0.5 + 0.5;''',1)
code=code.replace('                reflected_uv = reflected_clip.xy / reflected_clip.w * 0.5 + 0.5;',
    '                reflected_uv = reflected_clip.xy / reflected_clip.w * 0.5 + 0.5;\n                if (natural_reflection_flip_y) reflected_uv.y=1.0-reflected_uv.y;',1)
needle='            vec2 reflection_uv = clamp(reflected_uv, vec2(0.0), vec2(1.0));'
assert code.count(needle)==1
code=code.replace(needle,needle+'''
            vec2 reflection_size=vec2(textureSize(prototype_planar_reflection,0));
            vec2 margin=vec2(natural_reflection_edge_margin_px)/reflection_size;
            bool base_valid=planar_w>0.0001 && all(greaterThanEqual(reflected_uv,margin)) &&
                all(lessThanEqual(reflected_uv,vec2(1.0)-margin));
            bool perturb_reverted=false;
            vec2 perturb_delta=vec2(0.0);
            float reflection_weight=1.0;
            if (natural_reflection_protected) {
                reflection_uv=base_valid ? reflected_uv : vec2(0.5);
                if (base_valid && natural_reflection_perturbation && natural_reflection_shift_m>0.0) {
                    vec3 normal_world=normalize(mat3(INV_VIEW_MATRIX)*n);
                    vec4 world_position=INV_VIEW_MATRIX*vec4(VERTEX,1.0);
                    world_position.xz+=normal_world.xz*natural_reflection_shift_m;
                    vec4 shifted_clip=prototype_planar_view_projection*world_position;
                    vec2 shifted_uv=shifted_clip.xy/shifted_clip.w*0.5+0.5;
                    if (natural_reflection_flip_y) shifted_uv.y=1.0-shifted_uv.y;
                    perturb_delta=clamp(shifted_uv-reflected_uv,vec2(-natural_reflection_uv_limit),
                        vec2(natural_reflection_uv_limit));
                    vec2 proposed_uv=reflected_uv+perturb_delta;
                    if (shifted_clip.w>0.0001 && all(greaterThanEqual(proposed_uv,margin)) &&
                            all(lessThanEqual(proposed_uv,vec2(1.0)-margin))) {
                        reflection_uv=proposed_uv;
                    } else {
                        perturb_reverted=true;
                        perturb_delta=vec2(0.0);
                    }
                }
                float edge_distance_px=min(min(reflection_uv.x*reflection_size.x,
                    (1.0-reflection_uv.x)*reflection_size.x),min(reflection_uv.y*reflection_size.y,
                    (1.0-reflection_uv.y)*reflection_size.y))-natural_reflection_edge_margin_px;
                reflection_weight=base_valid ? (natural_reflection_edge_fade_px>0.0 ?
                    smoothstep(0.0,natural_reflection_edge_fade_px,edge_distance_px) : 1.0) : 0.0;
            }''',1)
code=code.replace('''                vec2 radius_uv = prototype_planar_reflection_softness_px /
                    vec2(textureSize(prototype_planar_reflection, 0));''','''                vec2 radius_uv = prototype_planar_reflection_softness_px /
                    vec2(textureSize(prototype_planar_reflection, 0));
                if (natural_reflection_protected) {
                    radius_uv=min(radius_uv,max(min(reflection_uv-margin,
                        vec2(1.0)-margin-reflection_uv),vec2(0.0)));
                }''',1)
code=code.replace('            reflected_scene = vec4(reflected_color, 1.0);','''            reflected_scene = vec4(reflected_color,1.0);
            if (natural_reflection_protected) {
                reflected_scene=vec4(mix(vec3(0.55,0.75,0.86),reflected_color,reflection_weight),reflection_weight);
            }
            if (natural_reflection_debug==1) natural_reflection_diag_color=vec3(reflection_uv,0.0);
            else if (natural_reflection_debug==2) natural_reflection_diag_color=vec3(length(perturb_delta)*32.0);
            else if (natural_reflection_debug==3) natural_reflection_diag_color=vec3(
                base_valid ? 0.0:1.0,perturb_reverted ? 1.0:0.0,
                base_valid ? 1.0-reflection_weight:0.0);
            else if (natural_reflection_debug==4) natural_reflection_diag_color=reflected_scene.rgb;
            else if (natural_reflection_debug==5) natural_reflection_diag_color=vec3(reflection_weight);''',1)
needle='''    if (natural_lighting_debug > 0) {
        EMISSION = vec3(0.0);
        ALPHA = 1.0;
    }'''
assert needle in code
code=code.replace(needle,needle+'''
    if (natural_reflection_debug>0) {
        EMISSION=natural_reflection_diag_color;
        natural_scatter_layer=vec3(0.0);
        natural_foam_layer=vec3(0.0);
        natural_glint_depth_gate=0.0;
        ALPHA=1.0;
    }''',1)
code=code.replace('mix(vec3(0.55,0.75,0.86),reflected_color,reflection_weight)','mix(natural_reflection_sky_linear,reflected_color,reflection_weight)')
code=re.sub(r'textureLod\(prototype_planar_reflection,\s*([\s\S]*?),\s*0\.0\)\.rgb',r'natural_reflection_read(\1)',code)
code=code.replace('void fragment() {','''vec3 natural_reflection_read(vec2 uv) {
    if (natural_reflection_srgb) return textureLod(natural_planar_reflection_srgb,uv,0.0).rgb;
    return textureLod(prototype_planar_reflection,uv,0.0).rgb;
}
void fragment() {''',1)
code='\n'.join(line if line.lstrip().startswith('uniform ') else
    re.sub(r'\bprototype_screen_sky_reflection_scale\b','(prototype_screen_sky_reflection_scale * natural_reflection_gain)',line)
    for line in code.split('\n'))
(a/'water_reflection.gdshader').write_text(code,encoding='utf-8')
base=json.loads((a/'base_v8_foam.json').read_text());base['resources']['water_shader']='res://assets/water_material_natural_candidate/water_reflection.gdshader'
(a/'base_v8_reflection.json').write_text(json.dumps(base,indent=2),encoding='utf-8')
bindings=json.loads((a/'contact_shape_geometry.json').read_text())
bindings.update(source_water_shader=base['resources']['water_shader'],source_sha256=hashlib.sha256((a/'water_reflection.gdshader').read_bytes()).hexdigest())
(a/'contact_reflection_geometry.json').write_text(json.dumps(bindings,indent=2),encoding='utf-8')
foam=json.loads((a/'foam_combination.json').read_text())
foam.update(base_profile='res://assets/water_material_natural_candidate/base_v8_reflection.json',
    water_shader=base['resources']['water_shader'],geometry_bindings='res://assets/water_material_natural_candidate/contact_reflection_geometry.json')
(a/'foam_reflection_derived.json').write_text(json.dumps(foam,indent=2),encoding='utf-8')
p={'reflection_schema_version':1,'foam_profile':'res://assets/water_material_natural_candidate/foam_combination.json',
    'foam_profile_sha256':hashlib.sha256((a/'foam_combination.json').read_bytes()).hexdigest(),
    'derived_foam_profile':'res://assets/water_material_natural_candidate/foam_reflection_derived.json',
    'base_profile':foam['base_profile'],'water_shader':foam['water_shader'],'sampling_mode':'legacy',
    'perturbation_enabled':False,'normal_shift_m':.25,'uv_shift_limit':.03,'edge_margin_px':2.,'edge_fade_px':8.,
    'reflection_strength':1.,'softness_px':0.}
(a/'reflection_baseline.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
(s/'reflection_baseline.tscn').write_text((s/'foam_combination.tscn').read_text().replace('foam_entry.gd','reflection_entry.gd').replace('foam_profile_path = "res://assets/water_material_natural_candidate/foam_combination.json"','reflection_profile_path = "res://assets/water_material_natural_candidate/reflection_baseline.json"'),encoding='utf-8')
p.update(reflection_schema_version=2,color_mode='srgb',sky_fallback='environment_background',sampling_mode='protected',perturbation_enabled=True)
(a/'reflection_corrected.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
(s/'reflection_corrected.tscn').write_text((s/'reflection_baseline.tscn').read_text().replace('reflection_baseline.json','reflection_corrected.json'),encoding='utf-8')
p.update(reflection_schema_version=3,projection_y_mode='viewport_top_left')
(a/'reflection_oriented.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
(s/'reflection_oriented.tscn').write_text((s/'reflection_baseline.tscn').read_text().replace('reflection_baseline.json','reflection_oriented.json'),encoding='utf-8')
print(hashlib.sha256((a/'water_reflection.gdshader').read_bytes()).hexdigest())
