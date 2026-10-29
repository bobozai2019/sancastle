"""Create isolated actual-profile integration of validated compiler variants."""
from pathlib import Path
import json, hashlib, copy

root = Path(__file__).resolve().parents[2]
assets = root / 'assets/water_material_natural_candidate'
scenes = root / 'scenes/water_material_natural_candidate'
res = lambda n: 'res://assets/water_material_natural_candidate/' + n
read = lambda n: json.loads((assets / n).read_text(encoding='utf8'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
created = []

def write(name, value):
    p = assets / name
    p.write_text(json.dumps(value, indent=2) + '\n', encoding='utf8')
    created.append(p)

base = read('base_v8_height.json')
base['resources']['water_shader'] = res('water_route_specialized.gdshader')
write('base_v8_compiled_v1.json', base)
style_base = copy.deepcopy(base)
for k in ['terrain_fixed_shader', 'terrain_coupled_shader']:
    style_base['resources'][k] = res('bed_geometry_specialized.gdshader')
write('base_v8_compiled_v1_style.json', style_base)
g = read('contact_height_geometry.json')
g.update(source_water_shader=res('water_route_specialized.gdshader'),
         source_sha256=sha(assets / 'water_route_specialized.gdshader'))
write('contact_compiled_v1_geometry.json', g)
f = read('foam_height_derived.json')
f.update(base_profile=res('base_v8_compiled_v1.json'),
         water_shader=res('water_route_specialized.gdshader'),
         geometry_bindings=res('contact_compiled_v1_geometry.json'))
write('foam_compiled_v1_derived.json', f)
r = read('reflection_height.json')
r.update(base_profile=res('base_v8_compiled_v1.json'),
         water_shader=res('water_route_specialized.gdshader'),
         derived_foam_profile=res('foam_compiled_v1_derived.json'))
write('reflection_compiled_v1.json', r)
s = read('style_height.json')
s.update(base_profile=res('base_v8_compiled_v1_style.json'),
         reflection_profile=res('reflection_compiled_v1.json'),
         reflection_profile_sha256=sha(assets / 'reflection_compiled_v1.json'),
         bed_shader=res('bed_geometry_specialized.gdshader'),
         bed_shader_sha256=sha(assets / 'bed_geometry_specialized.gdshader'))
write('style_compiled_v1.json', s)
bundle = {
    'bundle_schema_version': 1,
    'style_profile': res('style_compiled_v1.json'),
    'style_profile_sha256': sha(assets / 'style_compiled_v1.json'),
    'source_style_profile': res('style_height.json'),
    'source_style_profile_sha256': sha(assets / 'style_height.json'),
    'components': [],
}
for material, shader, index in [
    ('water', 'water_route_specialized.gdshader', 'water_route_full_index.json'),
    ('bed', 'bed_geometry_specialized.gdshader', 'bed_geometry_specialized_index.json'),
]:
    bundle['components'].append({
        'material': material, 'shader': res(shader),
        'shader_sha256': sha(assets / shader), 'index': res(index),
        'index_sha256': sha(assets / index),
    })
write('compiled_v1_bundle.json', bundle)
for kind, base_scene in [
    ('coupled', 'style_height_coupled.tscn'), ('fixed', 'style_height.tscn')
]:
    text = '''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/water_material_natural_candidate/BASE_SCENE" id="1_base"]
[ext_resource type="Script" path="res://assets/water_material_natural_candidate/compiled_worker_entry.gd" id="2_entry"]

[node name="WaterMaterialNaturalCompiled" instance=ExtResource("1_base")]
script = ExtResource("2_entry")
style_profile_path = "res://assets/water_material_natural_candidate/style_compiled_v1.json"
compiled_bundle_path = "res://assets/water_material_natural_candidate/compiled_v1_bundle.json"
compiled_bundle_sha256 = "BUNDLE_SHA"
'''.replace('BASE_SCENE', base_scene).replace(
        'BUNDLE_SHA', sha(assets / 'compiled_v1_bundle.json'))
    p = scenes / ('style_compiled_v1_' + kind + '.tscn')
    p.write_text(text, encoding='utf8')
    created.append(p)
(root / 'test_output/water_material_natural/t06_compiled_v1_generation.json').write_text(
    json.dumps({
        'command': 'python tests/water_material_natural/build_compiled_candidate.py',
        'source_style': res('style_height.json'),
        'source_style_sha256': sha(assets / 'style_height.json'),
        'created': [{'path': str(p), 'sha256': sha(p)} for p in created],
        'scope': 'Isolated compiler variants in actual profile chain; NOT formal merge or final gate.',
    }, indent=2), encoding='utf8')
print('Generated', len(created), 'isolated compiled_v1 files')
