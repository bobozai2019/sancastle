"""Generate a visual-only derivative, preserving all vertex/solver/contact inputs."""
import copy,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
A=ROOT/'assets/water_material_natural_candidate';S=ROOT/'scenes/water_material_natural_candidate'
res=lambda n:'res://assets/water_material_natural_candidate/'+n
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda n:json.loads((A/n).read_text())
def write(n,data):(A/n).write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
def replace(text,a,b,expected=1):
 assert text.count(a)==expected,(a[:100],text.count(a))
 return text.replace(a,b,1)

water=(A/'water_route_specialized.gdshader').read_text()
water_prefix=water.split('void fragment()')[0]
uniforms='''// Captured-water formula adapted to the project's meters, complete-state flow and clock.
uniform bool rdc_optics_enabled = false;
uniform bool rdc_normal_enabled = false;
uniform bool rdc_refracted_path = false;
uniform vec3 rdc_absorption_rgb = vec3(6.0,0.856013,0.336771);
uniform vec3 rdc_transmission_tint = vec3(0.758970,0.883854,0.968461);
uniform vec3 rdc_surface_color = vec3(0.801526,0.649696,0.506065);
uniform float rdc_distance_scale = 1.0;
uniform float rdc_normal_scale = 0.2;
uniform float rdc_normal_gain = 1.0;
uniform float rdc_time_scale = 1.0;
uniform float rdc_surface_gain = 1.0;
uniform float rdc_refraction_scale = 0.0121;
'''
water=replace(water,'void fragment() {',uniforms+'\nvoid fragment() {')
water=replace(water,'        vec3 detail_view = mat3(VIEW_MATRIX) *', '''        vec3 captured_detail = vec3(0.0,1.0,0.0);
        if (rdc_normal_enabled && use_detail_normals) {
            vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX,1.0)).xz;
            vec2 flow = clamp(vec2(texture(momentum_x_state,UV).r,
                texture(momentum_z_state,UV).r) / max(depth,0.02),vec2(-0.5),vec2(0.5));
            float phase = texture(natural_normal_texture,p*0.05).b + 0.8*t*rdc_time_scale;
            float a = fract(phase), b = fract(phase+0.5);
            vec2 normal_a = texture(natural_normal_texture,(p-flow*(2.0*b-1.0))*rdc_normal_scale+vec2(0.25)).rg;
            vec2 normal_b = texture(natural_normal_texture,(p-flow*(2.0*a-1.0))*rdc_normal_scale-vec2(0.25)).rg;
            detail = (mix(normal_b,normal_a,2.0*abs(a-0.5))*2.0-1.0)*rdc_normal_gain*attenuation;
            float squared = dot(detail,detail);
            if (squared>0.999) detail *= sqrt(0.999/squared);
            captured_detail = vec3(detail.x,sqrt(max(1.0-dot(detail,detail),0.0)),detail.y);
        }
        vec3 detail_view = mat3(VIEW_MATRIX) *''',expected=2)
water=replace(water,'        vec3 n = normalize(face_normal + detail_view);','''        vec3 captured_view = mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * captured_detail);
        vec3 n = normalize(face_normal + (rdc_normal_enabled && use_detail_normals && rdc_normal_gain>0.0 ? captured_view : detail_view));''')
water=replace(water,'        vec2 raw_candidate_uv = SCREEN_UV + offset;','''        if (rdc_optics_enabled) {
            offset = n.xy * rdc_refraction_scale * vec2(1.0,VIEWPORT_SIZE.x/VIEWPORT_SIZE.y);
        }
        vec2 raw_candidate_uv = SCREEN_UV + offset;''')
water=replace(water,'        vec2 path_uv = true ? SCREEN_UV : sampled_uv;','        vec2 path_uv = rdc_optics_enabled && rdc_refracted_path ? sampled_uv : SCREEN_UV;')
water=replace(water,'        if (prototype_optical_shallow_preserve) {','''        if (rdc_optics_enabled) {
            transmitted = bed_color * rdc_transmission_tint * exp(-path_length*rdc_distance_scale*rdc_absorption_rgb);
        }
        if (prototype_optical_shallow_preserve && !rdc_optics_enabled) {''')
water=replace(water,'        if (prototype_screen_scene_reflection) {','''        if (rdc_optics_enabled) {
            reflected_scene = vec4(rdc_surface_color,0.0);
        } else if (prototype_screen_scene_reflection) {''')
water=replace(water,'            ALBEDO = mix(transmitted, reflected_scene.rgb, reflect_weight);','''            if (rdc_optics_enabled) {
                transmitted *= 0.9+0.2*pow(clamp(cosine,0.0,1.0),6.0);
                reflect_weight = 0.75*fresnel*rdc_surface_gain;
            }
            ALBEDO = mix(transmitted, reflected_scene.rgb, reflect_weight);''')
water=replace(water,'            natural_scatter_layer = scatter * (1.0 - transmission) *','            natural_scatter_layer = (rdc_optics_enabled ? vec3(0.0) : scatter) * (1.0 - transmission) *')
water=replace(water,'            ALBEDO = vec3(transmission);','            ALBEDO = rdc_optics_enabled ? rdc_transmission_tint*exp(-path_length*rdc_distance_scale*rdc_absorption_rgb) : vec3(transmission);')
water=replace(water,'            ALBEDO = scatter;','            ALBEDO = rdc_optics_enabled ? vec3(0.0) : scatter;')
assert water.split(uniforms)[0]==water_prefix
(A/'rdc_water.gdshader').write_text(water,encoding='utf-8')

bed=(A/'bed_geometry_specialized.gdshader').read_text();bed_prefix=bed.split('void fragment()')[0]
bed_uniforms='''uniform bool rdc_caustics_enabled = false;
uniform sampler3D rdc_caustic_volume : filter_linear_mipmap, repeat_enable;
uniform sampler2D rdc_phase_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D rdc_momentum_x : filter_nearest, repeat_disable;
uniform sampler2D rdc_momentum_z : filter_nearest, repeat_disable;
uniform float rdc_caustic_scale = 0.25;
uniform float rdc_caustic_depth_decay = 1.2;
uniform float rdc_caustic_time_scale = 1.0;
'''
bed=replace(bed,'void fragment() {',bed_uniforms+'\nvoid fragment() {')
bed=replace(bed,'            if (prototype_texture_caustics) {','''            if (rdc_caustics_enabled) {
                // Local phase uses the existing captured normal B channel; original Sand.G is not mapped here.
                vec2 p = sand_world_position.xz;
                float clock = t*rdc_caustic_time_scale;
                float g = texture(rdc_phase_texture,p*0.3).b;
                float phase = g+0.5*clock;
                float a = fract(phase), b = fract(phase+0.5);
                vec2 flow = clamp(vec2(texture(rdc_momentum_x,UV).r,
                    texture(rdc_momentum_z,UV).r)/max(depth,0.02),vec2(-2.0),vec2(2.0));
                vec2 base_uv = p*rdc_caustic_scale+sand_world_normal.xz*0.1;
                float ca = texture(rdc_caustic_volume,vec3(base_uv-flow*(2.0*b-1.0)*0.1-vec2(0.5),(g+clock-0.5)*0.2)).r;
                float cb = texture(rdc_caustic_volume,vec3(base_uv-flow*(2.0*a-1.0)*0.1+vec2(0.5),(g+clock+0.5)*0.2)).r;
                line = mix(cb,ca,2.0*abs(a-0.5));
            } else if (prototype_texture_caustics) {''')
bed=replace(bed,'            ALBEDO += (prototype_texture_caustics ? vec3(0.31, 0.38, 0.31) :','''            if (rdc_caustics_enabled) {
                visibility = exp(-depth*rdc_caustic_depth_decay)*smoothstep(0.005,0.035,depth)*
                    smoothstep(0.2,0.3,max(sand_world_normal.y,0.0));
                if (natural_caustic_strength>0.0) ALBEDO = clamp(ALBEDO+vec3(line*visibility*natural_caustic_strength),vec3(0.0),vec3(1.0));
            } else ALBEDO += (prototype_texture_caustics ? vec3(0.31, 0.38, 0.31) :''')
assert bed.split(bed_uniforms)[0]==bed_prefix
(A/'rdc_bed.gdshader').write_text(bed,encoding='utf-8')

cfg={'rdc_schema_version':1,'caustic_texture':res('rdc_caustic_1105_mipped.res'),'caustic_texture_sha256':sha(A/'rdc_caustic_1105_mipped.res'),
 'parameters':{'rdc_optics_enabled':True,'rdc_normal_enabled':True,'rdc_refracted_path':False,'rdc_caustics_enabled':True,
 'rdc_absorption_rgb':[6.,0.856013,0.336771],'rdc_transmission_tint':[0.758970,0.883854,0.968461],
 'rdc_surface_color':[((c+.055)/1.055)**2.4 for c in [.73,.86,.93]],'rdc_distance_scale':1.,'rdc_normal_scale':.2,'rdc_normal_gain':1.,
 'rdc_time_scale':1.,'rdc_surface_gain':1.,'rdc_refraction_scale':.0121,'rdc_caustic_scale':.25,
 'rdc_caustic_depth_decay':1.2,'rdc_caustic_time_scale':1.}}
write('rdc_material_v1.json',cfg)
base=read('base_v8_compiled_v1.json');base['resources']['water_shader']=res('rdc_water.gdshader');write('rdc_base.json',base)
style_base=copy.deepcopy(base)
for key in ['terrain_fixed_shader','terrain_coupled_shader']:style_base['resources'][key]=res('rdc_bed.gdshader')
write('rdc_style_base.json',style_base)
geometry=read('contact_compiled_v1_geometry.json');geometry.update(source_water_shader=res('rdc_water.gdshader'),source_sha256=sha(A/'rdc_water.gdshader'));write('rdc_contact_geometry.json',geometry)
foam=read('foam_compiled_v1_derived.json');foam.update(base_profile=res('rdc_base.json'),water_shader=res('rdc_water.gdshader'),geometry_bindings=res('rdc_contact_geometry.json'));write('rdc_foam.json',foam)
reflection=read('reflection_compiled_v1.json');reflection.update(base_profile=res('rdc_base.json'),water_shader=res('rdc_water.gdshader'),derived_foam_profile=res('rdc_foam.json'));write('rdc_reflection.json',reflection)
style=read('style_reference_v1.json');style.update(style_schema_version=4,base_profile=res('rdc_style_base.json'),reflection_profile=res('rdc_reflection.json'),reflection_profile_sha256=sha(A/'rdc_reflection.json'),bed_shader=res('rdc_bed.gdshader'),bed_shader_sha256=sha(A/'rdc_bed.gdshader'),rdc_material_profile=res('rdc_material_v1.json'),rdc_material_profile_sha256=sha(A/'rdc_material_v1.json'),glint={'gain':1.,'exponent':1500.},detail_gain_multiplier=1.,normal_frequency_multiplier=1.)
write('rdc_style_v1.json',style)
bundle=read('reference_v1_bundle.json');bundle.update(style_profile=res('rdc_style_v1.json'),style_profile_sha256=sha(A/'rdc_style_v1.json'),source_style_profile=res('style_reference_v1.json'),source_style_profile_sha256=sha(A/'style_reference_v1.json'))
for component,source_index,shader,indexname in zip(bundle['components'],['water_route_full_index.json','bed_geometry_specialized_index.json'],['rdc_water.gdshader','rdc_bed.gdshader'],['rdc_water_index.json','rdc_bed_index.json']):
 index=read(source_index);index.update(source=str(A/Path(index['generated']).name),source_sha256=index['generated_sha256'],generated=str(A/shader),generated_sha256=sha(A/shader),scope='Visual-only captured-material adaptation; vertex geometry unchanged. Legacy fixed parameters remain guarded.')
 write(indexname,index);component.update(shader=res(shader),shader_sha256=sha(A/shader),index=res(indexname),index_sha256=sha(A/indexname))
write('rdc_bundle_v1.json',bundle)
for kind in ['fixed','coupled']:
 text=f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://scenes/water_material_natural_candidate/reference_v1_{kind}.tscn" id="1_base"]

[node name="WaterMaterialRdc" instance=ExtResource("1_base")]
style_profile_path = "{res('rdc_style_v1.json')}"
compiled_bundle_path = "{res('rdc_bundle_v1.json')}"
compiled_bundle_sha256 = "{sha(A/'rdc_bundle_v1.json')}"
'''
 (S/f'rdc_v1_{kind}.tscn').write_text(text,encoding='utf-8')
write('rdc_generation.json',{'generator':str(Path(__file__)),'generator_sha256':sha(Path(__file__)),'source_water_sha256':sha(A/'water_route_specialized.gdshader'),'source_bed_sha256':sha(A/'bed_geometry_specialized.gdshader'),'water_geometry_prefix_unchanged':True,'bed_geometry_prefix_unchanged':True,'water_shader_sha256':sha(A/'rdc_water.gdshader'),'bed_shader_sha256':sha(A/'rdc_bed.gdshader'),'adaptations':['Godot meters and complete-state momentum; original unit conversion unknown.','Unrefracted depth determines path; refraction color query remains independent.','Normal B replaces original Sand.G for caustic local phase.','Existing engine sun/shadows retained; Fresnel target uses captured constant without original shadow multiplier.','Existing shore coverage and foam composition retained.']})
print('Generated RDC visual derivative and strict profile/bundle; old reference resources preserved.')
