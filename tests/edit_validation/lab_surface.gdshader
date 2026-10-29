shader_type spatial;
render_mode cull_disabled;

uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform float extent_m = 8.0;
uniform bool is_water = false;
varying float water_depth;

void vertex() {
    vec2 cell_uv = (VERTEX.xz + vec2(extent_m * 0.5)) / extent_m;
    VERTEX.y = texture(rock_state, cell_uv).r + texture(sand_state, cell_uv).r;
    water_depth = texture(water_state, cell_uv).r;
    if (is_water) {
        VERTEX.y += water_depth + 0.002;
    }
}

void fragment() {
    if (is_water && water_depth <= 0.001) { discard; }
    ALBEDO = is_water ? vec3(0.1, 0.45, 0.65) : vec3(0.78, 0.65, 0.42);
    ROUGHNESS = is_water ? 0.2 : 0.85;
    ALPHA = is_water ? 0.55 : 1.0;
}
