shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D foam_state : filter_nearest, repeat_disable;
uniform sampler2D local_front_state : filter_nearest, repeat_disable;
uniform bool enabled = false;
uniform bool natural_contact_enabled = true;
uniform float natural_contact_gain = 1.0;
uniform float surface_offset_m = 0.016;
uniform float wet_epsilon_m = 0.001;

vec4 cell_state(ivec2 cell) {
    ivec2 safe_cell = clamp(cell, ivec2(0), ivec2(255));
    float bed = texelFetch(rock_state, safe_cell, 0).r +
        texelFetch(sand_state, safe_cell, 0).r;
    float depth = max(texelFetch(water_state, safe_cell, 0).r, 0.0);
    float wet = step(wet_epsilon_m, depth);
    return vec4(bed, (bed + depth) * wet, wet, depth);
}

vec2 display_surface(vec2 uv) {
    vec2 cell = uv * 256.0 - vec2(0.5);
    ivec2 low = ivec2(floor(cell));
    vec2 blend = fract(cell);
    blend = blend * blend * (vec2(3.0) - vec2(2.0) * blend);
    vec4 s00 = cell_state(low);
    vec4 s10 = cell_state(low + ivec2(1, 0));
    vec4 s01 = cell_state(low + ivec2(0, 1));
    vec4 s11 = cell_state(low + ivec2(1, 1));
    vec4 combined = mix(mix(s00, s10, blend.x), mix(s01, s11, blend.x), blend.y);
    float depth = 0.0;
    if (combined.z > 0.0) {
        float local_max = max(max(s00.w, s10.w), max(s01.w, s11.w));
        depth = min(max(combined.y / combined.z - combined.x, 0.0) *
            combined.z, local_max);
    }
    return vec2(combined.x, depth);
}

void vertex() {
    vec2 surface = display_surface(UV);
    VERTEX.y = surface.x + surface.y + surface_offset_m;
}

void fragment() {
    if (!enabled || !natural_contact_enabled) {
        discard;
    }
    vec2 surface = display_surface(UV);
    float depth = surface.y;
    if (depth <= wet_epsilon_m || depth >= 0.075) {
        discard;
    }
    ivec2 cell = clamp(ivec2(round(UV * 256.0 - vec2(0.5))),
        ivec2(0), ivec2(255));
    float nearest_dry = 10.0;
    float nearby_foam = 0.0;
    float nearby_front = 0.0;
    for (int dz = -2; dz <= 2; dz++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 sample_cell = clamp(cell + ivec2(dx, dz),
                ivec2(0), ivec2(255));
            float sample_depth = texelFetch(water_state, sample_cell, 0).r;
            if (sample_depth <= wet_epsilon_m) {
                nearest_dry = min(nearest_dry,
                    length(vec2(float(dx), float(dz)) + vec2(cell) -
                        (UV * 256.0 - vec2(0.5))));
            }
            nearby_foam = max(nearby_foam,
                texelFetch(foam_state, sample_cell, 0).r);
            nearby_front = max(nearby_front,
                texelFetch(local_front_state, sample_cell, 0).g);
        }
    }
    float edge = 1.0 - smoothstep(0.55, 2.2, nearest_dry);
    float activity = smoothstep(0.015, 0.08, nearby_foam) *
        smoothstep(0.0008, 0.0025, nearby_front);
    float shallow = 1.0 - smoothstep(0.025, 0.075, depth);
    float breakup = 0.68 + 0.32 * sin(UV.x * 522.0 +
        1.7 * sin(UV.y * 719.0));
    ALBEDO = vec3(0.91, 0.97, 0.98);
    ALPHA = clamp(edge * activity * shallow * breakup * 0.9, 0.0, 0.9);
    ALPHA = min(ALPHA * natural_contact_gain,1.0);
    if (ALPHA < 0.03) {
        discard;
    }
}
