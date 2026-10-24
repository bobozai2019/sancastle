"""Add bounded two-phase flow to the accepted static coverage, without reshaping it."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ASSETS=ROOT/'assets/water_foam'
source=ASSETS/'static_candidate.gdshader'
shader=source.read_text(encoding='utf-8')
shader=shader.replace('uniform float foam_hole_strength = 1.0;','''uniform float foam_hole_strength = 1.0;
uniform float foam_flow_cycle_s = 4.0;
uniform float foam_flow_gain = 1.0;
uniform float foam_flow_speed_cap_m_s = 2.0;''')
old='''        float detail = texture(foam_detail_texture, uv_m * foam_detail_scale_per_m).r;'''
new='''        vec2 flux = vec2(textureLod(momentum_x_state, uv, 0.0).r,
            textureLod(momentum_z_state, uv, 0.0).r);
        vec2 velocity = flux / max(depth, 0.02);
        float speed = length(velocity);
        velocity *= min(1.0, max(foam_flow_speed_cap_m_s, 0.0) / max(speed, 0.00001));
        velocity *= max(foam_flow_gain, 0.0);
        float cycle = max(foam_flow_cycle_s, 0.5);
        float phase_a = fract(t / cycle);
        float phase_b = fract(t / cycle + 0.5);
        float weight_a = 1.0 - abs(phase_a * 2.0 - 1.0);
        vec2 base_uv = uv_m * foam_detail_scale_per_m;
        vec2 flow_uv_a = (uv_m - velocity * ((phase_a - 0.5) * cycle)) * foam_detail_scale_per_m;
        vec2 flow_uv_b = (uv_m - velocity * ((phase_b - 0.5) * cycle)) * foam_detail_scale_per_m;
        vec2 dx = dFdx(base_uv);
        vec2 dy = dFdy(base_uv);
        float detail_a = textureGrad(foam_detail_texture, flow_uv_a, dx, dy).r;
        float detail_b = textureGrad(foam_detail_texture, flow_uv_b, dx, dy).r;
        // Equal samples (zero velocity) must remain exactly constant in time.
        float detail = detail_a + (detail_b - detail_a) * (1.0 - weight_a);'''
assert shader.count(old)==1
shader=shader.replace(old,new)
shader=shader.replace('uniform float foam_flow_cycle_s = 4.0;','uniform bool foam_flow_debug = false;\nuniform float foam_flow_cycle_s = 4.0;')
light=shader.index('\nvoid light()')
fragment_end=shader.rfind('}',0,light)
shader=shader[:fragment_end]+'''    if (foam_flow_debug && foam_detail_mode == 1) {
        EMISSION = vec3(natural_foam_layer.r * 6.0);
        natural_scatter_layer = vec3(0.0);
        natural_foam_layer = vec3(0.0);
        natural_glint_depth_gate = 0.0;
        ALPHA = 1.0;
    }
'''+shader[fragment_end:]
dest=ASSETS/'flow_candidate.gdshader'
dest.write_text(shader,encoding='utf-8')
identity=dict(source_shader=source.relative_to(ROOT).as_posix(),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),flow_shader_sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),cycle_s=4,flow_gain=1,speed_cap_m_s=2,clock='Existing completed-state t parameter',extra_inputs='Two existing published momentum samplers; depth is existing fragment input',detail_reads=2,stage='T02 candidate, not yet verified')
(ASSETS/'flow_generation.json').write_text(json.dumps(identity,indent=2),encoding='utf-8')
print(json.dumps(identity,indent=2))
