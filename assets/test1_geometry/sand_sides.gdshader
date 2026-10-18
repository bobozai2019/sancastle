shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
varying float side_height;

float bed_cell(ivec2 p) {
    p = clamp(p, ivec2(0), ivec2(255));
    return texelFetch(rock_state, p, 0).r + texelFetch(sand_state, p, 0).r;
}

float bed_at(vec2 uv) {
    vec2 p = uv * 256.0 - vec2(0.5);
    ivec2 a = ivec2(floor(p));
    vec2 f = fract(p);
    float v00 = bed_cell(a);
    float v10 = bed_cell(a + ivec2(1, 0));
    float v01 = bed_cell(a + ivec2(0, 1));
    float v11 = bed_cell(a + ivec2(1, 1));
    if (f.x + f.y <= 1.0) return v00 + (v10-v00)*f.x + (v01-v00)*f.y;
    return v11 + (v01-v11)*(1.0-f.x) + (v10-v11)*(1.0-f.y);
}

void vertex() {
    VERTEX.y = mix(-0.1, bed_at(UV), COLOR.r);
    side_height = COLOR.r;
}

void fragment() {
    ALBEDO = mix(vec3(0.46, 0.34, 0.18), vec3(0.76, 0.59, 0.35), side_height);
    ROUGHNESS = 0.96;
}
