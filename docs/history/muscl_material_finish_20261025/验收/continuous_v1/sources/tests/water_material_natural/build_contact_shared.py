"""Generate a foam-only contact surface from the actual candidate water geometry."""
import re,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
a=ROOT/'assets/water_material_natural_candidate'
water=(a/'water_foam.gdshader').read_text()
def function(name):
    match=re.search(r'\b(?:vec[234]|float|void)\s+'+name+r'\s*\(',water)
    assert match,name
    start=water.index('{',match.start());depth=1;end=start+1
    while depth:
        depth += (water[end]=='{')-(water[end]=='}');end+=1
    return water[match.start():end]
functions='\n\n'.join(function(n) for n in ['state_cell','coupled_bed_triangle_at','coupled_bed_render_mesh_at','display_surface','prototype_crest'])
vertex=function('vertex')
geometry=vertex[vertex.index('    vec3 surface = display_surface(UV);'):vertex.index('    if (prototype_eta_normals')]
geometry=geometry.replace('    prototype_crest_lift_v = crest_lift;\n','')
geometry+='    VERTEX.y += natural_contact_separation_m;\n'
original=(a/'contact_foam.gdshader').read_text()
fragment=original[original.index('void fragment()'):]
fragment=fragment.replace('vec2 surface = display_surface(UV);','vec3 surface = display_surface(UV);')
needed=set(re.findall(r'\b[A-Za-z_]\w*\b',functions+geometry))
declarations=[]
for line in water.splitlines():
    m=re.match(r'uniform\s+\w+\s+(\w+)\b',line)
    if m and m[1] in needed:declarations.append(line)
assert len(declarations)>10
header=original[:original.index('vec4 cell_state')]
# Keep existing samplers/epsilon declarations; append the remaining declarations.
existing=set(re.findall(r'uniform\s+\w+\s+(\w+)\b',header))
added=[line for line in declarations if re.match(r'uniform\s+\w+\s+(\w+)',line)[1] not in existing]
header+='\n'.join(added)+'\nuniform bool natural_contact_shared_surface = false;\nuniform float natural_contact_separation_m = 0.001;\n\n'
code=header+functions+'\n\nvoid vertex() {\n    if (natural_contact_shared_surface) {\n'+geometry+'\n    } else {\n        vec3 surface=display_surface(UV);\n        VERTEX.y=surface.x+surface.y+surface_offset_m;\n    }\n}\n\n'+fragment
(a/'contact_shared.gdshader').write_text(code,encoding='utf-8')
profile=json.loads((a/'foam_baseline.json').read_text())
profile['foam_schema_version']=2
profile['contact_shader']='res://assets/water_material_natural_candidate/contact_shared.gdshader'
profile['contact'].update(surface_mode='shared_water',separation_m=.001)
(a/'foam_shared_surface.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
s=ROOT/'scenes/water_material_natural_candidate'
(s/'foam_shared_surface.tscn').write_text((s/'foam_baseline.tscn').read_text().replace('foam_baseline.json','foam_shared_surface.json'),encoding='utf-8')
geometry_names=[re.match(r'uniform\s+\w+\s+(\w+)',line)[1] for line in declarations]
(a/'contact_geometry_bindings.json').write_text(json.dumps({'source_water_shader':'res://assets/water_material_natural_candidate/water_foam.gdshader',
    'source_sha256':hashlib.sha256((a/'water_foam.gdshader').read_bytes()).hexdigest(),'uniform_declarations':declarations,'geometry_uniforms':geometry_names,
    'generated_shader_sha256':hashlib.sha256((a/'contact_shared.gdshader').read_bytes()).hexdigest()},indent=2),encoding='utf-8')
print(json.dumps({'geometry_uniforms':geometry_names,'generated_shader_sha256':hashlib.sha256((a/'contact_shared.gdshader').read_bytes()).hexdigest()}))
