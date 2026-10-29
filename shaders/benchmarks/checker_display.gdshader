shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D state_texture : filter_nearest;

void fragment() {
    float value = texture(state_texture, UV).r;
    ALBEDO = vec3(value, value * 0.75, 0.12);
}
