"""Build owned normal-only assets after G0; shared release stays byte-identical."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
assets=ROOT/'assets/water_material_natural_candidate'
scenes=ROOT/'scenes/water_material_natural_candidate'
assets.mkdir(exist_ok=True);scenes.mkdir(exist_ok=True)
base=ROOT/'assets/test1_beach/test1_water_front.gdshader'
code=base.read_text(encoding='utf-8')
code=code.replace('uniform bool use_detail_normals = true;', '''uniform bool use_detail_normals = true;
// Normal-only candidate v1: macro geometry is unchanged.
uniform int natural_normal_mode = 1; // 0 off, 1 legacy, 2 texture
uniform sampler2D natural_normal_texture : filter_linear_mipmap, repeat_enable;
uniform vec4 natural_layer0 = vec4(0.18, 0.035, 0.06, 0.0);
uniform vec4 natural_layer1 = vec4(0.47, -0.022, 0.025, 0.0);
uniform vec2 natural_direction0 = vec2(1.0, 0.0);
uniform vec2 natural_direction1 = vec2(0.6, 0.8);
uniform int natural_normal_debug = 0;''')
old='''        vec2 detail = vec2(
            sin(uv_m.x * 3.1 + uv_m.y * 1.7 - t * 1.2),
            cos(uv_m.y * 2.8 - uv_m.x * 1.4 - t * 0.9)) *
            0.075 * attenuation;'''
new='''        vec2 detail = vec2(0.0);
        if (use_detail_normals && natural_normal_mode == 1) {
            detail = vec2(sin(uv_m.x * 3.1 + uv_m.y * 1.7 - t * 1.2),
                cos(uv_m.y * 2.8 - uv_m.x * 1.4 - t * 0.9)) * 0.075 * attenuation;
        } else if (use_detail_normals && natural_normal_mode == 2) {
            // RG signed slopes in local XZ; rotated UV/slopes share a basis.
            vec2 q0 = vec2(dot(uv_m, natural_direction0),
                dot(uv_m, vec2(-natural_direction0.y, natural_direction0.x)));
            vec2 q1 = vec2(dot(uv_m, natural_direction1),
                dot(uv_m, vec2(-natural_direction1.y, natural_direction1.x)));
            vec2 a = texture(natural_normal_texture,
                (q0 - vec2(t * natural_layer0.y, 0.0)) * natural_layer0.x).rg * 2.0 - 1.0;
            vec2 b = texture(natural_normal_texture,
                (q1 - vec2(t * natural_layer1.y, 0.0)) * natural_layer1.x).rg * 2.0 - 1.0;
            vec2 a_local = natural_direction0 * a.x + vec2(-natural_direction0.y, natural_direction0.x) * a.y;
            vec2 b_local = natural_direction1 * b.x + vec2(-natural_direction1.y, natural_direction1.x) * b.y;
            detail = (a_local * natural_layer0.z + b_local * natural_layer1.z) * attenuation;
        }'''
assert code.count(old)==1
code=code.replace(old,new)
old='''        if (prototype_refraction_fallback_debug) {'''
new='''        if (natural_normal_debug == 1) {
            ALBEDO = normalize(mat3(INV_VIEW_MATRIX) * n) * 0.5 + 0.5;
            ALPHA = 1.0;
        } else if (natural_normal_debug == 2) {
            ALBEDO = vec3(detail.x * 3.0 + 0.5, 0.5, detail.y * 3.0 + 0.5);
            ALPHA = 1.0;
        }
        if (prototype_refraction_fallback_debug) {'''
assert code.count(old)==1
code=code.replace(old,new)
(assets/'water_normal.gdshader').write_text(code,encoding='utf-8')
shutil.copyfile(ROOT/'test_output/water_material_natural/t00_normal_recovery/normal_681_mip0.png',assets/'water_normal_681.png')
p=json.loads((ROOT/'assets/test1_beach/test1_beach_release.json').read_text())
p['resources']['water_shader']='res://assets/water_material_natural_candidate/water_normal.gdshader'
(assets/'base_v8_normal.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
p=json.loads((ROOT/'test_output/water_material_natural/t00_interface/candidate_interface_v1.json').read_text())
p['normal_detail']['texture']='res://assets/water_material_natural_candidate/water_normal_681.png'
for mode in ('off','legacy_sine','texture_layers'):
    p['normal_detail']['mode']=mode
    (assets/(mode+'.json')).write_text(json.dumps(p,indent=2),encoding='utf-8')
    scene='''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/sandcastle_test1_beach_fixed.tscn" id="1_base"]
[ext_resource type="Script" path="res://assets/water_material_natural_candidate/normal_entry.gd" id="2_entry"]

[node name="WaterMaterialNaturalFixed" instance=ExtResource("1_base")]
script = ExtResource("2_entry")
candidate_profile_path = "res://assets/water_material_natural_candidate/MODE.json"
'''.replace('MODE',mode)
    (scenes/(mode+'.tscn')).write_text(scene,encoding='utf-8')
print('Built three isolated normal candidates; no formal files edited')
