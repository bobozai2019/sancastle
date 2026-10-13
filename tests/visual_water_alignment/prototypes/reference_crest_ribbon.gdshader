shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D rock_state : filter_linear, repeat_disable;
uniform sampler2D sand_state : filter_linear, repeat_disable;
uniform sampler2D water_state : filter_linear, repeat_disable;
uniform sampler2D foam_state : filter_linear, repeat_disable;
uniform float crest_height_m = 0.25;
uniform bool prototype_full_body = false;
uniform bool prototype_attached_body = false;
uniform bool prototype_attached_smooth_mask = false;
uniform vec3 foam_tint = vec3(0.93, 0.96, 0.97);

varying float ribbon_mask;
varying float ribbon_layer;
varying vec2 ribbon_position_uv;

float edge_score(float x, float z) {
    vec2 p = vec2(x, z);
    float center = textureLod(foam_state, p, 0.0).r;
    float ahead = textureLod(foam_state,
        vec2(min(x + 2.0 / 256.0, 1.0), z), 0.0).r;
    return max(center - ahead, 0.0) * smoothstep(0.08, 0.40, center);
}

float main_crest_lift(vec2 uv, float depth) {
    vec2 step_uv = vec2(1.0 / 256.0, 0.0);
    float center = textureLod(foam_state, uv, 0.0).r;
    float left = textureLod(foam_state,
        clamp(uv - step_uv, vec2(0.0), vec2(1.0)), 0.0).r;
    float right = textureLod(foam_state,
        clamp(uv + step_uv, vec2(0.0), vec2(1.0)), 0.0).r;
    float coverage = max(center, 0.6 * max(left, right));
    return crest_height_m * smoothstep(0.04, 0.45, coverage) *
        smoothstep(0.012, 0.08, depth);
}

float main_vertex_height(ivec2 cell) {
    cell = clamp(cell, ivec2(0), ivec2(255));
    float bed = texelFetch(rock_state, cell, 0).r +
        texelFetch(sand_state, cell, 0).r;
    float depth = max(texelFetch(water_state, cell, 0).r, 0.0);
    vec2 uv = (vec2(cell) + vec2(0.5)) / 256.0;
    return bed + depth + 0.003 + main_crest_lift(uv, depth);
}

float main_surface_height(vec2 uv) {
    // Ribbon rows coincide with the main grid's z vertex rows. Reconstruct
    // the actual main-mesh edge between adjacent x vertex centres.
    vec2 cell_position = uv * 256.0 - vec2(0.5);
    int row = clamp(int(round(cell_position.y)), 0, 255);
    int left = clamp(int(floor(cell_position.x)), 0, 255);
    float fraction = clamp(cell_position.x - float(left), 0.0, 1.0);
    float h0 = main_vertex_height(ivec2(left, row));
    float h1 = main_vertex_height(ivec2(min(left + 1, 255), row));
    return mix(h0, h1, fraction);
}

void vertex() {
    float z = UV.y;
    ribbon_layer = UV.x;
    float sum_weight = 0.0;
    float sum_x = 0.0;
    float peak = 0.0;
    // The small z neighbourhood gives adjacent ribbon rows a common front.
    // This is a display-only search through the existing foam field.
    for (int i = 0; i < 64; i++) {
        float x = 0.45 + (float(i) + 0.5) * (0.53 / 64.0);
        float score = edge_score(x, z) + 0.5 * edge_score(x,
            clamp(z - 1.0 / 256.0, 0.0, 1.0)) + 0.5 * edge_score(x,
            clamp(z + 1.0 / 256.0, 0.0, 1.0));
        float weight = score * score;
        sum_weight += weight;
        sum_x += x * weight;
        peak = max(peak, score);
    }
    float front_x = sum_weight > 0.000001 ? sum_x / sum_weight : 0.75;
    ribbon_position_uv = vec2(front_x, z);
    float bed = textureLod(rock_state, ribbon_position_uv, 0.0).r +
        textureLod(sand_state, ribbon_position_uv, 0.0).r;
    float depth = max(textureLod(water_state, ribbon_position_uv, 0.0).r, 0.0);
    float foam = textureLod(foam_state, ribbon_position_uv, 0.0).r;
    if (prototype_attached_body && prototype_attached_smooth_mask) {
        vec2 near_step = vec2(0.0, 2.0 / 256.0);
        vec2 far_step = near_step * 2.0;
        foam = 0.4 * foam + 0.2 * (
            textureLod(foam_state,
                clamp(ribbon_position_uv - near_step, vec2(0.0), vec2(1.0)), 0.0).r +
            textureLod(foam_state,
                clamp(ribbon_position_uv + near_step, vec2(0.0), vec2(1.0)), 0.0).r) +
            0.1 * (
            textureLod(foam_state,
                clamp(ribbon_position_uv - far_step, vec2(0.0), vec2(1.0)), 0.0).r +
            textureLod(foam_state,
                clamp(ribbon_position_uv + far_step, vec2(0.0), vec2(1.0)), 0.0).r);
    }
    ribbon_mask = smoothstep(0.008, 0.06, peak) *
        smoothstep(0.06, 0.35, foam) * smoothstep(0.05, 0.12, depth);
    float height = crest_height_m * ribbon_mask;
    float t = ribbon_layer;
    float x_offset = prototype_full_body ?
        (-0.40 + 0.85 * t - 0.25 * sin(t * 3.14159265)) * ribbon_mask :
        (-0.12 + 0.42 * t - 0.12 * sin(t * 3.14159265)) * ribbon_mask;
    if (prototype_attached_body) {
        // Both ends coincide with the main water surface at their own x.
        // The cubic x path folds the leading lip back toward the surface.
        float attached_offset = (-0.36 + 1.25 * t - 0.75 * t * t * t) *
            ribbon_mask;
        VERTEX.x = front_x * 32.0 - 16.0 + attached_offset;
        vec2 attached_uv = clamp(vec2((VERTEX.x + 16.0) / 32.0, z),
            vec2(0.0), vec2(1.0));
        ribbon_position_uv = attached_uv;
        VERTEX.y = main_surface_height(attached_uv) +
            0.16 * ribbon_mask * sin(t * 3.14159265);
    } else {
        VERTEX.x = front_x * 32.0 - 16.0 + x_offset;
        VERTEX.y = bed + depth + 0.006 + 0.015 +
            height * sin(t * 3.14159265 * 0.90);
    }
}

void fragment() {
    if (ribbon_mask < 0.05) {
        discard;
    }
    float t = ribbon_layer;
    float breakup = texture(foam_state,
        clamp(ribbon_position_uv + vec2(0.0, 1.5 / 256.0),
            vec2(0.0), vec2(1.0))).r;
    if (prototype_attached_body) {
        float edge_fade = smoothstep(0.0, 0.15, t) *
            (1.0 - smoothstep(0.82, 1.0, t));
        ALBEDO = foam_tint * (0.76 + 0.22 * smoothstep(0.18, 0.72, t));
        ALPHA = ribbon_mask * edge_fade *
            (0.74 + 0.16 * smoothstep(0.04, 0.40, breakup));
    } else {
        float colour = prototype_full_body ?
            (0.72 + 0.25 * smoothstep(0.10, 0.75, t)) :
            (0.78 + 0.19 * smoothstep(0.15, 0.85, t));
        ALBEDO = foam_tint * colour;
        ALPHA = ribbon_mask * (prototype_full_body ?
            (0.62 + 0.30 * smoothstep(0.05, 0.65, t)) :
            (0.18 + 0.72 * smoothstep(0.05, 0.65, t))) *
            (0.76 + 0.20 * smoothstep(0.04, 0.40, breakup));
    }
}
