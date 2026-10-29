"""Generate diagnostic fragment-only macro-normal modes, preserving all vertex code."""
from pathlib import Path
import hashlib, json

root = Path(__file__).resolve().parents[2]
source = root/'assets/water_material_natural_candidate/water_reflection.gdshader'
target = root/'assets/water_material_natural_candidate/water_macro.gdshader'
s = source.read_text(encoding='utf-8')
old = '''        vec3 face_normal = FRONT_FACING ? NORMAL : -NORMAL;
        vec3 n = normalize(face_normal + detail_view);
        if (prototype_screen_face_normal && dot(normalize(VIEW), n) < 0.0) {
            n = -n;
        }'''
new = '''        vec3 face_normal = FRONT_FACING ? NORMAL : -NORMAL;
        if (natural_macro_normal_mode > 0 && natural_macro_normal_mode <= 3) {
            if (dot(normalize(VIEW), face_normal) < 0.0) face_normal = -face_normal;
            if (natural_macro_normal_mode >= 2) {
                vec3 geometric = cross(dFdx(VERTEX), dFdy(VERTEX));
                float geometric_l2 = dot(geometric, geometric);
                if (geometric_l2 > 1e-12) {
                    geometric *= inversesqrt(geometric_l2);
                    if (dot(normalize(VIEW), geometric) < 0.0) geometric = -geometric;
                    float geometric_weight = 1.0;
                    if (natural_macro_normal_mode == 3) {
                        vec2 cell_uv = vec2(1.0 / 256.0, 0.0);
                        float min_depth = depth;
                        min_depth = min(min_depth, textureLod(water_state, clamp(UV + cell_uv, vec2(0.0), vec2(1.0)), 0.0).r);
                        min_depth = min(min_depth, textureLod(water_state, clamp(UV - cell_uv, vec2(0.0), vec2(1.0)), 0.0).r);
                        min_depth = min(min_depth, textureLod(water_state, clamp(UV + cell_uv.yx, vec2(0.0), vec2(1.0)), 0.0).r);
                        min_depth = min(min_depth, textureLod(water_state, clamp(UV - cell_uv.yx, vec2(0.0), vec2(1.0)), 0.0).r);
                        geometric_weight = smoothstep(0.008, 0.065, min_depth);
                    }
                    vec3 mixed_macro = mix(face_normal, geometric, geometric_weight);
                    float mixed_l2 = dot(mixed_macro, mixed_macro);
                    if (mixed_l2 > 1e-12) face_normal = mixed_macro * inversesqrt(mixed_l2);
                }
            }
        }
        vec3 n = normalize(face_normal + detail_view);
        if (natural_macro_normal_mode == 0 && prototype_screen_face_normal && dot(normalize(VIEW), n) < 0.0) {
            n = -n;
        }'''
assert s.count(old) == 1
uniform = 'uniform int natural_macro_normal_mode = 0;\n'
result = s.replace('void fragment() {',uniform+'\nvoid fragment() {',1).replace(old,new,1)
assert result.split('void fragment() {')[0].replace(uniform+'\n','') == s.split('void fragment() {')[0]
target.write_text(result,encoding='utf-8')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
manifest = {'source':str(source),'source_sha256':sha(source),'target':str(target),'target_sha256':sha(target),
    'geometry_prefix_unchanged_after_removing_new_uniform':True,
    'geometry_prefix_sha256':hashlib.sha256(s.split('void fragment() {')[0].encode()).hexdigest(),
    'command':'python tests/water_material_natural/build_macro_normal_probe.py',
    'scope':'Fragment-only shading diagnostic. No vertex, geometry helper, authoritative input or collision changes. Not selected in composition yet.'}
(target.parent/'water_macro_generation.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps(manifest))
