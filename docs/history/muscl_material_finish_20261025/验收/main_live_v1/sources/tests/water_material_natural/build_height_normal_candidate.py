"""Wire minimal height-surface shading as an explicit schema2 composition."""
from pathlib import Path
import hashlib, json, copy

root=Path(__file__).resolve().parents[2]
assets=root/'assets/water_material_natural_candidate'
scenes=root/'scenes/water_material_natural_candidate'
res=lambda name:'res://assets/water_material_natural_candidate/'+name
read=lambda name:json.loads((assets/name).read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,value): (assets/name).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
source=assets/'water_reflection.gdshader'
s=source.read_text(encoding='utf-8')
old='if (prototype_screen_face_normal && dot(normalize(VIEW), n) < 0.0)'
assert s.count(old)==1
uniform='uniform bool natural_height_surface_normal = false;\n'
t=s.replace('void fragment() {',uniform+'\nvoid fragment() {',1).replace(old,'if (!natural_height_surface_normal && prototype_screen_face_normal && dot(normalize(VIEW), n) < 0.0)',1)
assert t.split('void fragment() {')[0].replace(uniform+'\n','')==s.split('void fragment() {')[0]
target=assets/'water_height.gdshader';target.write_text(t,encoding='utf-8')
base=read('base_v8_reflection.json');base['resources']['water_shader']=res(target.name)
write('base_v8_height.json',base)
stylebase=copy.deepcopy(base)
for k in ['terrain_fixed_shader','terrain_coupled_shader']:stylebase['resources'][k]=res('bed_style.gdshader')
write('base_v8_height_style.json',stylebase)
geometry=read('contact_reflection_geometry.json')
geometry['source_water_shader']=res(target.name);geometry['source_sha256']=sha(target)
write('contact_height_geometry.json',geometry)
foam=read('foam_reflection_derived.json')
foam['base_profile']=res('base_v8_height.json');foam['water_shader']=res(target.name);foam['geometry_bindings']=res('contact_height_geometry.json')
write('foam_height_derived.json',foam)
reflection=read('reflection_oriented.json')
reflection['base_profile']=res('base_v8_height.json');reflection['water_shader']=res(target.name);reflection['derived_foam_profile']=res('foam_height_derived.json')
write('reflection_height.json',reflection)
style=read('style_combination.json')
style.update(style_schema_version=2,reflection_profile=res('reflection_height.json'),reflection_profile_sha256=sha(assets/'reflection_height.json'),base_profile=res('base_v8_height_style.json'))
for name,mode in [('style_height_baseline','legacy_eta'),('style_height','height_surface')]:
    style['macro_normal_mode']=mode;write(name+'.json',style)
    scene=(scenes/'style_combination.tscn').read_text(encoding='utf-8').replace('/style_combination.json','/'+name+'.json')
    (scenes/(name+'.tscn')).write_text(scene,encoding='utf-8')
foreground=(scenes/'style_foreground.tscn').read_text(encoding='utf-8').replace('/style_combination.json','/style_height.json')
(scenes/'style_height_foreground.tscn').write_text(foreground,encoding='utf-8')
manifest={'source':str(source),'source_sha256':sha(source),'target':str(target),'target_sha256':sha(target),
    'geometry_prefix_unchanged_after_removing_new_uniform':True,
    'geometry_prefix_sha256':hashlib.sha256(s.split('void fragment() {')[0].encode()).hexdigest(),
    'command':'python tests/water_material_natural/build_height_normal_candidate.py',
    'scope':'Explicit schema2 composition; equivalent to diagnostic mode4, preserving all vertex/helper code. Final selection pending related negatives and continuous review.'}
write('height_normal_generation.json',manifest)
print(json.dumps(manifest))
