"""Isolated lighting snapshots; never overwrite the verified normal shader."""
import json
import hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
assets=ROOT/'assets/water_material_natural_candidate'
scenes=ROOT/'scenes/water_material_natural_candidate'
code=(assets/'water_normal.gdshader').read_text()
code=code.replace('uniform bool prototype_screen_world_glint = false;', '''uniform bool prototype_screen_world_glint = false;
uniform bool natural_glint_enabled = true;
uniform float natural_glint_gain = 0.32;
uniform float natural_glint_exponent = 42.0;
uniform float natural_scatter_direct_fraction = 0.0;
uniform float natural_foam_direct_fraction = 0.0;
uniform int natural_lighting_debug = 0;''')
code=code.replace('void fragment() {', 'void fragment() {\n    vec3 natural_sun_term = vec3(0.0);')
old='''            if (prototype_screen_world_glint && use_specular) {'''
new='''            if ((prototype_screen_world_glint || natural_glint_enabled) && use_specular) {'''
assert code.count(old)==1
code=code.replace(old,new)
old='''                float glint = pow(max(dot(n, half_view), 0.0), 42.0) *
                    slope_gate * smoothstep(0.02, 0.09, depth) * 0.32;
                ALBEDO += vec3(1.0, 0.96, 0.86) * glint;'''
new='''                float glint = pow(max(dot(n, half_view), 0.0), natural_glint_exponent) *
                    smoothstep(0.008, 0.05, depth) * natural_glint_gain;
                natural_sun_term = vec3(1.0, 0.96, 0.86) * glint;
                ALBEDO += natural_sun_term;'''
assert code.count(old)==1
code=code.replace(old,new)
code=code.replace('        if (natural_normal_debug == 1) {', '''        if (natural_lighting_debug == 1) {
            ALBEDO = natural_sun_term;
            ALPHA = 1.0;
        }
        if (natural_normal_debug == 1) {''')
(assets/'water_manual_glint.gdshader').write_text(code,encoding='utf-8')
base=json.loads((ROOT/'assets/test1_beach/test1_beach_release.json').read_text())
base['resources']['water_shader']='res://assets/water_material_natural_candidate/water_manual_glint.gdshader'
(assets/'base_v8_manual_glint.json').write_text(json.dumps(base,indent=2),encoding='utf-8')
normal=assets/'texture_layers.json'
profile={'lighting_schema_version':1,'normal_profile':'res://assets/water_material_natural_candidate/texture_layers.json',
         'normal_profile_sha256':hashlib.sha256(normal.read_bytes()).hexdigest(),'route':'manual_glint',
         'base_profile':'res://assets/water_material_natural_candidate/base_v8_manual_glint.json',
         'water_shader':'res://assets/water_material_natural_candidate/water_manual_glint.gdshader',
         'sun_glint_enabled':True,'sun_glint_gain':.32,'sun_glint_exponent':42.,'shadow_enabled':False,
         'scatter_direct_fraction':0.,'foam_direct_fraction':0.}
(assets/'lighting_manual.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
scene='''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/water_material_natural_candidate/rdc_v1_fixed.tscn" id="1_base"]
[ext_resource type="Script" path="res://assets/water_material_natural_candidate/lighting_entry.gd" id="2_entry"]

[node name="WaterMaterialNaturalLighting" instance=ExtResource("1_base")]
script = ExtResource("2_entry")
lighting_profile_path = "res://assets/water_material_natural_candidate/lighting_manual.json"

[node name="LightFacing" type="Camera3D" parent="CameraAnchors"]
position = Vector3(-10, 22, -14)
rotation_degrees = Vector3(-52, -144.46, 0)
fov = 55.0
'''
(scenes/'lighting_manual.tscn').write_text(scene,encoding='utf-8')
print('Isolated manual-glint candidate built')
