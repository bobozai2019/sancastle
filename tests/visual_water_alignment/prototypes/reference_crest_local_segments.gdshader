shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// W07 branch-aware trial. Each short Z segment selects one nearby 2D front;
// no triangles connect different X candidates or distant coastline rows.
uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D local_front_state : filter_linear, repeat_disable;
uniform bool display_reconstruction = true;
varying float segment_mask;
varying float segment_layer;

vec4 state_cell(ivec2 cell) {
    ivec2 p = clamp(cell, ivec2(0), ivec2(255));
    float bed = texelFetch(rock_state, p, 0).r +
        texelFetch(sand_state, p, 0).r;
    float depth = max(texelFetch(water_state, p, 0).r, 0.0);
    float wet = step(0.001, depth);
    return vec4(bed, (bed + depth) * wet, wet, depth);
}

vec2 surface_at(vec2 uv) {
    if (!display_reconstruction) {
        float bed = textureLod(rock_state, uv, 0.0).r +
            textureLod(sand_state, uv, 0.0).r;
        return vec2(bed, max(textureLod(water_state, uv, 0.0).r, 0.0));
    }
    vec2 cell = uv * 256.0 - vec2(0.5);
    ivec2 low = ivec2(floor(cell));
    vec2 t = fract(cell);
    vec2 blend = t * t * (vec2(3.0) - vec2(2.0) * t);
    vec4 a = mix(state_cell(low), state_cell(low + ivec2(1, 0)), blend.x);
    vec4 b = mix(state_cell(low + ivec2(0, 1)),
        state_cell(low + ivec2(1, 1)), blend.x);
    vec4 s = mix(a, b, blend.y);
    float depth = 0.0;
    if (s.z > 0.0) {
        float wet_eta = s.y / s.z;
        float local_max = max(max(state_cell(low).w,
            state_cell(low + ivec2(1, 0)).w),
            max(state_cell(low + ivec2(0, 1)).w,
                state_cell(low + ivec2(1, 1)).w));
        depth = min(max(wet_eta - s.x, 0.0) * s.z, local_max);
    }
    return vec2(s.x, depth);
}

float main_crest(vec2 uv, float depth) {
    vec2 front = textureLod(local_front_state, uv, 0.0).rg;
    float distance_cells = uv.x * 256.0 - 0.5 - front.x;
    float shoulder = smoothstep(-7.5, -1.0, distance_cells);
    float face = 1.0 - smoothstep(0.0, 1.8, distance_cells);
    float lift = 0.25 * smoothstep(0.0012, 0.0045, front.y) *
        shoulder * face * smoothstep(0.012, 0.065, depth);
    return min(lift, max(depth, 0.0) * 1.5);
}

vec2 profile_point(int layer) {
    if (layer == 1) return vec2(-0.45, 0.25);
    if (layer == 2) return vec2(-0.26, 0.65);
    if (layer == 3) return vec2(-0.08, 1.00);
    if (layer == 4) return vec2(0.06, 1.15);
    if (layer == 5) return vec2(0.18, 0.90);
    if (layer == 6) return vec2(0.08, 0.55);
    if (layer == 7) return vec2(0.14, 0.18);
    if (layer == 8) return vec2(0.28, 0.0);
    return vec2(-0.65, 0.0);
}

void vertex() {
    float candidate_cell = UV2.x * 256.0 - 0.5;
    vec2 seed = textureLod(local_front_state, UV2, 0.0).rg;
    vec2 endpoint = textureLod(local_front_state,
        vec2(UV2.x, UV.y), 0.0).rg;
    float front_cell = endpoint.y > 0.0001 ? endpoint.x : seed.x;
    vec2 center_uv = vec2((front_cell + 0.5) / 256.0, UV.y);
    vec2 center_surface = surface_at(center_uv);
    float forward_depth = max(textureLod(water_state,
        vec2((min(front_cell + 3.0, 255.0) + 0.5) / 256.0,
            UV.y), 0.0).r, 0.0);
    float selected = 1.0 - step(2.0, abs(seed.x - candidate_cell));
    segment_mask = selected * smoothstep(0.002, 0.005, seed.y) *
        smoothstep(0.001, 0.003, endpoint.y) *
        smoothstep(0.01, 0.05, forward_depth) *
        smoothstep(0.04, 0.12, center_surface.y);
    float amplitude = min(0.25, center_surface.y * 1.5) * segment_mask;
    int layer = clamp(int(round(UV.x * 8.0)), 0, 8);
    vec2 shape = profile_point(layer);
    float front_m = (front_cell + 0.5) * 0.125 - 16.0;
    float x_m = front_m + shape.x * 0.35 *
        (0.45 + 0.55 * segment_mask);
    vec2 sample_uv = vec2(clamp((x_m + 16.0) / 32.0, 0.0, 1.0), UV.y);
    vec2 surface = surface_at(sample_uv);
    float extra = layer == 0 || layer == 8 ? 0.0 :
        amplitude * 0.45 * shape.y;
    VERTEX.x = x_m;
    VERTEX.y = surface.x + surface.y + 0.006 +
        main_crest(sample_uv, surface.y) + extra;
    segment_layer = UV.x;
}

void fragment() {
    if (segment_mask < 0.02) {
        discard;
    }
    float crown = smoothstep(0.12, 0.38, segment_layer) *
        (1.0 - smoothstep(0.72, 0.98, segment_layer));
    ALBEDO = mix(vec3(0.05, 0.42, 0.48),
        vec3(0.27, 0.73, 0.75), crown * 0.68);
}
