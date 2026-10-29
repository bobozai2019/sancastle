"""Versioned engine-light experiment: emission preserves already shaded scene copy."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
assets=ROOT/'assets/water_material_natural_candidate'
scenes=ROOT/'scenes/water_material_natural_candidate'
code=(assets/'water_normal.gdshader').read_text()
code=code.replace('render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;',
                  'render_mode ambient_light_disabled, cull_disabled, blend_mix, depth_draw_always;')
code=code.replace('uniform bool prototype_screen_world_glint = false;', '''uniform bool prototype_screen_world_glint = false;
uniform bool natural_glint_enabled = true;
uniform float natural_glint_gain = 0.32;
uniform float natural_glint_exponent = 42.0;
uniform float natural_scatter_direct_fraction = 0.45;
uniform float natural_foam_direct_fraction = 0.50;
uniform int natural_lighting_debug = 0;
varying vec3 natural_scatter_layer;
varying vec3 natural_foam_layer;
varying float natural_glint_depth_gate;''')
code=code.replace('void fragment() {', '''void fragment() {
    natural_scatter_layer = vec3(0.0);
    natural_foam_layer = vec3(0.0);
    natural_glint_depth_gate = 0.0;''')
code=code.replace('        float surface_distance = -VERTEX.z;', '''        NORMAL = n;
        natural_glint_depth_gate = smoothstep(0.008, 0.05, depth);
        float surface_distance = -VERTEX.z;''')
old='''            ALBEDO = mix(transmitted, reflected_scene.rgb,
                (0.025 + 0.42 * fresnel) * prototype_screen_sky_reflection_scale);'''
new='''            float reflect_weight = (0.025 + 0.42 * fresnel) * prototype_screen_sky_reflection_scale;
            ALBEDO = mix(transmitted, reflected_scene.rgb, reflect_weight);
            float preserved_bed = prototype_optical_shallow_preserve ?
                1.0 - smoothstep(0.03, 0.18, depth) : 0.0;
            natural_scatter_layer = scatter * (1.0 - transmission) *
                (1.0 - preserved_bed) * (1.0 - reflect_weight);'''
assert code.count(old)==1
code=code.replace(old,new)
old='''            prototype_apply_whitewater(ALBEDO, ALPHA, UV, uv_m, depth, t,
                prototype_crest_lift_v, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z);'''
new='''            float white_fraction = prototype_whitewater(UV, uv_m, depth, t,
                prototype_crest_lift_v) * test1_whitewater_gain *
                (prototype_crest_white_face ? 0.94 : 0.78);
            natural_scatter_layer *= 1.0 - white_fraction;
            natural_foam_layer = foam_tint * white_fraction;
            prototype_apply_whitewater(ALBEDO, ALPHA, UV, uv_m, depth, t,
                prototype_crest_lift_v, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z);'''
assert code.count(old)==1
code=code.replace(old,new)
# Extra debug paths must remain emission-only, without unrelated light terms.
pos=code.rfind('\n}')
code=code[:pos]+'''
    vec3 direct_layer = natural_scatter_layer * natural_scatter_direct_fraction +
        natural_foam_layer * natural_foam_direct_fraction;
    EMISSION = ALBEDO - direct_layer;
    ALBEDO = vec3(1.0);
    SPECULAR = 0.0;
    if (natural_normal_debug > 0) {
        EMISSION += direct_layer;
        natural_scatter_layer = vec3(0.0);
        natural_foam_layer = vec3(0.0);
        natural_glint_depth_gate = 0.0;
    }
    if (natural_lighting_debug > 0) {
        EMISSION = vec3(0.0);
        ALPHA = 1.0;
    }
'''+code[pos:]
code+='''

void light() {
    if (LIGHT_IS_DIRECTIONAL) {
        vec3 irradiance = LIGHT_COLOR / PI * ATTENUATION;
        vec3 direct = (natural_scatter_layer * natural_scatter_direct_fraction +
            natural_foam_layer * natural_foam_direct_fraction) *
            max(dot(NORMAL, LIGHT), 0.0) * irradiance;
        vec3 half_direction = normalize(VIEW + LIGHT);
        float glint = natural_glint_enabled && use_specular ?
            pow(max(dot(NORMAL, half_direction), 0.0), natural_glint_exponent) *
            natural_glint_gain * natural_glint_depth_gate : 0.0;
        vec3 specular_term = vec3(1.0, 0.96, 0.86) * glint * irradiance;
        if (natural_lighting_debug == 1) {
            SPECULAR_LIGHT += specular_term;
        } else if (natural_lighting_debug == 2) {
            DIFFUSE_LIGHT += vec3(ATTENUATION);
        } else if (natural_lighting_debug == 3) {
            DIFFUSE_LIGHT += natural_scatter_layer * max(dot(NORMAL, LIGHT), 0.0) * irradiance;
        } else if (natural_lighting_debug == 4) {
            DIFFUSE_LIGHT += natural_foam_layer * max(dot(NORMAL, LIGHT), 0.0) * irradiance;
        } else {
            DIFFUSE_LIGHT += direct;
            SPECULAR_LIGHT += specular_term;
        }
    }
}
'''
(assets/'water_engine_light.gdshader').write_text(code,encoding='utf-8')
foam=(ROOT/'assets/test1_beach/test1_front_foam_splats.gdshader').read_text()
foam=foam.replace('render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;',
                  'render_mode ambient_light_disabled, cull_disabled, blend_mix, depth_draw_never;')
foam=foam.replace('varying vec2 splat_uv;', '''uniform float natural_foam_direct_fraction = 0.50;
uniform int natural_lighting_debug = 0;
varying vec3 natural_foam_color;
varying vec2 splat_uv;''')
pos=foam.rfind('\n}')
foam=foam[:pos]+'''
    vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    NORMAL = dot(face, VIEW) < 0.0 ? -face : face;
    natural_foam_color = ALBEDO;
    EMISSION = ALBEDO * (1.0 - natural_foam_direct_fraction);
    ALBEDO = vec3(1.0);
    SPECULAR = 0.0;
    if (natural_lighting_debug > 0) {
        EMISSION = vec3(0.0);
    }
    if (natural_lighting_debug == 2) {
        if (ALPHA < 0.05) { discard; }
        ALPHA = 1.0;
    }
'''+foam[pos:]
foam+='''
void light() {
    if (LIGHT_IS_DIRECTIONAL) {
        if (natural_lighting_debug == 2) {
            DIFFUSE_LIGHT += vec3(ATTENUATION);
        } else {
            DIFFUSE_LIGHT += natural_foam_color * natural_foam_direct_fraction *
                max(dot(NORMAL, LIGHT), 0.0) * LIGHT_COLOR / PI * ATTENUATION;
        }
    }
}
'''
(assets/'foam_engine_light.gdshader').write_text(foam,encoding='utf-8')
base=json.loads((ROOT/'assets/test1_beach/test1_beach_release.json').read_text())
base['resources']['water_shader']='res://assets/water_material_natural_candidate/water_engine_light.gdshader'
(assets/'base_v8_engine_light.json').write_text(json.dumps(base,indent=2),encoding='utf-8')
profile=json.loads((assets/'lighting_manual.json').read_text())
profile.update(route='engine_light',base_profile='res://assets/water_material_natural_candidate/base_v8_engine_light.json',
               water_shader=base['resources']['water_shader'],shadow_enabled=True,
               scatter_direct_fraction=.45,foam_direct_fraction=.50,
               lighting_schema_version=2,foam_shader='res://assets/water_material_natural_candidate/foam_engine_light.gdshader')
(assets/'lighting_engine.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
scene=(scenes/'lighting_manual.tscn').read_text().replace('lighting_manual.json','lighting_engine.json')
(scenes/'lighting_engine.tscn').write_text(scene,encoding='utf-8')
fixture=scene.replace('load_steps=3','load_steps=5')
fixture=fixture.replace('[node name="WaterMaterialNaturalLighting"', '''[sub_resource type="BoxMesh" id="ShadowBoxMesh"]
size = Vector3(1.3, 5, 1.3)

[sub_resource type="StandardMaterial3D" id="ShadowBoxMaterial"]
shading_mode = 0
albedo_color = Color(0.9, 0.02, 0.7, 1)

[node name="WaterMaterialNaturalLighting"''')
fixture+='''

[node name="ShadowOccluder" type="MeshInstance3D" parent="."]
position = Vector3(-6, 2.5, -3)
mesh = SubResource("ShadowBoxMesh")
material_override = SubResource("ShadowBoxMaterial")
cast_shadow = 1

[node name="FoamShadowOccluder" type="MeshInstance3D" parent="."]
position = Vector3(3.8, 2.5, 5.8)
mesh = SubResource("ShadowBoxMesh")
material_override = SubResource("ShadowBoxMaterial")
cast_shadow = 1
'''
(scenes/'lighting_shadow_fixture.tscn').write_text(fixture,encoding='utf-8')
print('Engine light experiment built; shadow acceptance unverified')
