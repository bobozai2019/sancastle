shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D rock_state : filter_linear, repeat_disable;
uniform sampler2D sand_state : filter_linear, repeat_disable;
uniform sampler2D water_state : filter_linear, repeat_disable;
uniform sampler2D foam_state : filter_linear, repeat_disable;
uniform float crest_height_m = 0.25;
uniform float forward_m = 0.05;
uniform vec3 foam_tint = vec3(0.93, 0.96, 0.97);

varying float curtain_mask;
varying float curtain_layer;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
    vec2 cell_uv = UV2;
    float bed = textureLod(rock_state, UV, 0.0).r +
        textureLod(sand_state, UV, 0.0).r;
    float depth = max(textureLod(water_state, UV, 0.0).r, 0.0);
    float center = textureLod(foam_state, cell_uv, 0.0).r;
    float ahead = textureLod(foam_state,
        clamp(cell_uv + vec2(1.0 / 256.0, 0.0), vec2(0.0), vec2(1.0)), 0.0).r;
    float wet = smoothstep(0.05, 0.12, depth);
    curtain_mask = smoothstep(0.14, 0.45, center) *
        smoothstep(0.01, 0.16, center - ahead) * wet;
    float coverage = textureLod(foam_state, UV, 0.0).r;
    float lift = crest_height_m * smoothstep(0.04, 0.45, coverage) *
        smoothstep(0.012, 0.08, depth);
    curtain_layer = COLOR.r;
    // Three height layers bend the sheet forward at mid-height while the top
    // reconnects to the lifted water surface.
    VERTEX.x += forward_m * curtain_mask *
        sin(curtain_layer * 3.14159265);
    VERTEX.y = bed + depth + 0.006 + mix(0.01, lift, curtain_layer);
}

void fragment() {
    if (curtain_mask < 0.05) {
        discard;
    }
    float grain = hash21(floor(UV * vec2(256.0, 512.0)));
    ALBEDO = foam_tint * (0.88 + 0.12 * grain);
    float lower_fade = smoothstep(0.0, 0.8, curtain_layer);
    ALPHA = clamp(curtain_mask * (0.25 + 0.65 * lower_fade) *
        (0.72 + 0.22 * grain), 0.0, 0.95);
}
