from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
a=ROOT/'assets/water_material_natural_candidate'
code=(a/'water_optics.gdshader').read_text()
code=code.replace('uniform int natural_path_mode = 0;',
    'uniform int natural_path_mode = 0;\n// Diagnostic only; not a published composition-profile field.\nuniform bool natural_path_unrefracted = false;')
old='''        float sampled_depth = textureLod(prototype_scene_depth, sampled_uv, 0.0).r;
        vec4 sampled_view_h = INV_PROJECTION_MATRIX * vec4(sampled_uv * 2.0 - 1.0, sampled_depth, 1.0);'''
new='''        vec2 path_uv = natural_path_unrefracted ? SCREEN_UV : sampled_uv;
        float sampled_depth = textureLod(prototype_scene_depth, path_uv, 0.0).r;
        vec4 sampled_view_h = INV_PROJECTION_MATRIX * vec4(path_uv * 2.0 - 1.0, sampled_depth, 1.0);'''
assert old in code
(a/'water_path_diagnostic.gdshader').write_text(code.replace(old,new),encoding='utf-8')
