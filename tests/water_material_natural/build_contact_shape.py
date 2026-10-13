import json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];a=ROOT/'assets/water_material_natural_candidate';s=ROOT/'scenes/water_material_natural_candidate'
code=(a/'contact_shared.gdshader').read_text()
code=code.replace('uniform bool natural_contact_shared_surface', 'uniform int natural_contact_shape_mode = 0;\nuniform float natural_contact_shape_scale_per_m = 6.0;\nuniform bool natural_contact_shared_surface',1)
code=code.replace('void fragment() {','''float contact_hash(vec2 p) {
    return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
float contact_noise(vec2 p) {
    vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(contact_hash(i),contact_hash(i+vec2(1.0,0.0)),f.x),
        mix(contact_hash(i+vec2(0.0,1.0)),contact_hash(i+vec2(1.0)),f.x),f.y);
}
void fragment() {''')
code=code.replace('    ALBEDO = vec3(0.91, 0.97, 0.98);','''    if (natural_contact_shape_mode == 1) {
        vec2 p=(UV*32.0-vec2(16.0))*natural_contact_shape_scale_per_m;
        float layers=0.65*contact_noise(p)+0.35*contact_noise(p*2.1+vec2(7.3,11.7));
        float lace=smoothstep(0.22,0.72,layers);
        float core=1.0-smoothstep(0.55,0.95,nearest_dry);
        breakup=mix(0.12+0.88*lace,0.80+0.20*lace,core);
    }
    ALBEDO = vec3(0.91, 0.97, 0.98);''')
(a/'contact_shape.gdshader').write_text(code,encoding='utf-8')
bindings=json.loads((a/'contact_geometry_bindings.json').read_text())
bindings['generated_shader_sha256']=hashlib.sha256((a/'contact_shape.gdshader').read_bytes()).hexdigest()
(a/'contact_shape_geometry.json').write_text(json.dumps(bindings,indent=2),encoding='utf-8')
p=json.loads((a/'foam_shared_surface.json').read_text())
p.update(foam_schema_version=3,geometry_bindings='res://assets/water_material_natural_candidate/contact_shape_geometry.json',
    contact_shader='res://assets/water_material_natural_candidate/contact_shape.gdshader')
p['contact'].update(shape_mode='legacy',shape_scale_per_m=6.)
(a/'foam_shape_baseline.json').write_text(json.dumps(p,indent=2),encoding='utf-8')
(s/'foam_shape_baseline.tscn').write_text((s/'foam_shared_surface.tscn').read_text().replace('foam_shared_surface.json','foam_shape_baseline.json'),encoding='utf-8')
