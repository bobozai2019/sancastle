from pathlib import Path
import json,hashlib,re
ROOT=Path(__file__).resolve().parents[2];a=ROOT/'assets/water_material_natural_candidate';s=ROOT/'scenes/water_material_natural_candidate'
code=(a/'water_optics_unrefracted.gdshader').read_text()
code=code.replace('uniform sampler2D rock_state','uniform float natural_main_foam_gain = 1.0;\nuniform sampler2D rock_state',1)
code='\n'.join(line if line.lstrip().startswith('uniform ') else re.sub(r'\btest1_whitewater_gain\b','(test1_whitewater_gain * natural_main_foam_gain)',line) for line in code.split('\n'))
(a/'water_foam.gdshader').write_text(code,encoding='utf-8')
fine=(a/'foam_engine_light.gdshader').read_text().replace('varying vec3 natural_foam_color;','''uniform bool natural_fine_enabled = true;
uniform int natural_fine_size_mode = 0;
uniform vec2 natural_fine_size_range = vec2(0.65,1.3);
uniform float natural_fine_gain = 1.0;
uniform float natural_cluster_strength = 0.0;
uniform float natural_cluster_scale_per_m = 1.0;
varying vec3 natural_foam_color;''')
fine=fine.replace('void vertex() {','''float natural_cluster(vec2 p) {
    vec2 q=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash21(q),hash21(q+vec2(1.0,0.0)),f.x),
        mix(hash21(q+vec2(0.0,1.0)),hash21(q+vec2(1.0)),f.x),f.y);
}
void vertex() {''')
fine=fine.replace('float variation = mix(0.65, 1.3, hash21(id + vec2(17.0, 31.0)));','''float size_seed = hash21(id + vec2(17.0,31.0));
    float variation = natural_fine_size_mode == 0 ? mix(0.65,1.3,size_seed) :
        mix(natural_fine_size_range.x,natural_fine_size_range.y,pow(size_seed,2.4));''')
fine=fine.replace('void fragment() {','void fragment() {\n    if (!natural_fine_enabled) { discard; }')
fine=fine.replace('    vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));','''    float cluster = smoothstep(0.20,0.75,natural_cluster(domain_uv*32.0*natural_cluster_scale_per_m));
    ALPHA = min(ALPHA * natural_fine_gain * mix(1.0,cluster,natural_cluster_strength),1.0);
    vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));''')
(a/'foam_distribution.gdshader').write_text(fine,encoding='utf-8')
contact=(ROOT/'tests/visual_water_alignment/prototypes/reference_shore_contact_overlay.gdshader').read_text().replace('uniform bool enabled = false;','uniform bool enabled = false;\nuniform bool natural_contact_enabled = true;\nuniform float natural_contact_gain = 1.0;').replace('if (!enabled) {','if (!enabled || !natural_contact_enabled) {')
contact=contact.replace('    if (ALPHA < 0.03) {','    ALPHA = min(ALPHA * natural_contact_gain,1.0);\n    if (ALPHA < 0.03) {')
(a/'contact_foam.gdshader').write_text(contact,encoding='utf-8')
base=json.loads((a/'base_v8_optics_unrefracted.json').read_text());base['resources']['water_shader']='res://assets/water_material_natural_candidate/water_foam.gdshader'
(a/'base_v8_foam.json').write_text(json.dumps(base,indent=2),encoding='utf-8')
profile={'foam_schema_version':1,'optics_profile':'res://assets/water_material_natural_candidate/optics_selected.json',
    'optics_profile_sha256':hashlib.sha256((a/'optics_selected.json').read_bytes()).hexdigest(),
    'base_profile':'res://assets/water_material_natural_candidate/base_v8_foam.json','water_shader':base['resources']['water_shader'],
    'fine_shader':'res://assets/water_material_natural_candidate/foam_distribution.gdshader','contact_shader':'res://assets/water_material_natural_candidate/contact_foam.gdshader',
    'main':{'enabled':True,'gain':1.0},
    'fine':{'enabled':True,'size_mode':'legacy','size_range':[.65,1.3],'gain':1.0,'clustering_strength':0.0,'clustering_scale_per_m':1.0,'jitter_m':.02,'direct_fraction':.50},
    'contact':{'enabled':True,'gain':1.0,'surface_offset_m':.016}}
(a/'foam_baseline.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
scene=(s/'optics_selected.tscn').read_text().replace('optics_entry.gd','foam_entry.gd').replace('optics_profile_path = "res://assets/water_material_natural_candidate/optics_selected.json"','foam_profile_path = "res://assets/water_material_natural_candidate/foam_baseline.json"')
(s/'foam_baseline.tscn').write_text(scene,encoding='utf-8')
