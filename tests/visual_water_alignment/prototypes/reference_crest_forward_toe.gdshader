shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;

uniform sampler2D rock_state : filter_linear, repeat_disable;
uniform sampler2D sand_state : filter_linear, repeat_disable;
uniform sampler2D water_state : filter_linear, repeat_disable;
uniform sampler2D foam_state : filter_linear, repeat_disable;
uniform sampler2D foam_previous_state : filter_linear, repeat_disable;
uniform sampler2D rise_front_state : filter_linear, repeat_disable;
uniform float crest_height_m = 0.25;
uniform bool prototype_full_body = false;
uniform bool prototype_attached_body = false;
uniform bool prototype_attached_smooth_mask = false;
uniform bool prototype_use_front_field = false;
uniform bool prototype_solid_lip = false;
uniform bool prototype_water_body = false;
uniform bool prototype_main_rise = true;
uniform vec2 prototype_row_window = vec2(0.0, 1.0);
uniform vec3 foam_tint = vec3(0.93, 0.96, 0.97);

varying float ribbon_mask;
varying float ribbon_layer;
varying vec2 ribbon_position_uv;

float edge_score(float x, float z) {
    vec2 p = vec2(x, z);
    float depth = max(textureLod(water_state, p, 0.0).r, 0.0);
    float previous_depth = max(textureLod(foam_previous_state, p, 0.0).g, 0.0);
    return max(depth - previous_depth, 0.0) * smoothstep(0.01, 0.04, depth);
}

float main_crest_lift(vec2 uv, float depth) {
    if (prototype_use_front_field) {
        vec2 front = textureLod(rise_front_state, vec2(uv.y, 0.5), 0.0).rg;
        float cell_x = uv.x * 256.0 - 0.5;
        float distance_cells = cell_x - front.x;
        float back_shoulder = smoothstep(-12.0, -1.0, distance_cells);
        float advancing_face = 1.0 - smoothstep(0.0, 2.0, distance_cells);
        return crest_height_m * smoothstep(0.0025, 0.0050, front.y) *
            back_shoulder * advancing_face *
            smoothstep(0.012, 0.065, depth);
    }
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
    return bed + depth + 0.003 +
        (prototype_main_rise ? main_crest_lift(uv, depth) : 0.0);
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
    if (!prototype_use_front_field) {
        // Original per-vertex search retained for a measured W07 comparison.
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
    }
    float front_x = sum_weight > 0.0000000001 ? sum_x / sum_weight : 0.75;
    if (prototype_use_front_field) {
        vec2 front = textureLod(rise_front_state, vec2(z, 0.5), 0.0).rg;
        front_x = (front.x + 0.5) / 256.0;
        // Bridge short inactive row gaps without shifting the front position.
        // This is only a W07 morphology probe; a production field would do
        // this once in compute rather than seven times per ribbon vertex.
        for (int row_offset = -12; row_offset <= 12; row_offset += 4) {
            float row_uv = clamp(z + float(row_offset) / 256.0,
                0.5 / 256.0, 255.5 / 256.0);
            peak = max(peak, textureLod(rise_front_state,
                vec2(row_uv, 0.5), 0.0).g);
        }
    }
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
    ribbon_mask = (prototype_use_front_field ?
        smoothstep(0.0025, 0.0045, peak) :
        smoothstep(0.0055, 0.0090, peak)) *
        smoothstep(0.012, 0.04, depth);
    ribbon_mask *= step(prototype_row_window.x, z) * step(z, prototype_row_window.y);
    float height = crest_height_m * ribbon_mask;
    float t = ribbon_layer;
    float x_offset = prototype_full_body ?
        (-0.40 + 0.85 * t - 0.25 * sin(t * 3.14159265)) * ribbon_mask :
        (-0.12 + 0.42 * t - 0.12 * sin(t * 3.14159265)) * ribbon_mask;
    if (prototype_solid_lip) {
        // A closed-looking breaking cross section: back shoulder, crown,
        // forward overhang, underside, then toe. All points stay attached to
        // the same main-surface height reconstruction at their own x.
        int layer = clamp(int(round(t * 10.0)), 0, 10);
        vec2 offset = vec2(-0.70, 0.0);
        if (layer == 1) offset = vec2(-0.50, 0.06);
        else if (layer == 2) offset = vec2(-0.25, 0.14);
        else if (layer == 3) offset = vec2(0.00, 0.22);
        else if (layer == 4) offset = vec2(0.25, 0.25);
        else if (layer == 5) offset = vec2(0.42, 0.23);
        else if (layer == 6) offset = vec2(0.48, 0.17);
        else if (layer == 7) offset = vec2(0.43, 0.10);
        else if (layer == 8) offset = vec2(0.32, 0.05);
        else if (layer == 9) offset = vec2(0.33, 0.015);
        else if (layer == 10) offset = vec2(0.58, 0.0);
        VERTEX.x = front_x * 32.0 - 16.0 + offset.x * ribbon_mask;
        vec2 attached_uv = clamp(vec2((VERTEX.x + 16.0) / 32.0, z),
            vec2(0.0), vec2(1.0));
        ribbon_position_uv = attached_uv;
        VERTEX.y = main_surface_height(attached_uv) +
            offset.y * ribbon_mask;
    } else if (prototype_attached_body) {
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
    if (prototype_solid_lip) {
        float edge_fade = smoothstep(0.0, 0.10, t) *
            (1.0 - smoothstep(0.90, 1.0, t));
        float crown = smoothstep(0.15, 0.55, t) *
            (1.0 - 0.24 * smoothstep(0.65, 0.90, t));
        if (prototype_water_body) {
            float bright_lip = smoothstep(0.29, 0.43, t) *
                (1.0 - smoothstep(0.57, 0.69, t));
            float underside = smoothstep(0.58, 0.75, t);
            vec3 water_body = mix(vec3(0.21, 0.59, 0.65),
                vec3(0.075, 0.34, 0.43), underside);
            ALBEDO = mix(water_body, foam_tint, bright_lip *
                (0.82 + 0.18 * smoothstep(0.04, 0.40, breakup)));
            ALPHA = ribbon_mask * edge_fade * (0.78 + 0.17 * bright_lip);
        } else {
            ALBEDO = foam_tint * (0.70 + 0.28 * crown);
            ALPHA = ribbon_mask * edge_fade *
                (0.82 + 0.14 * smoothstep(0.04, 0.40, breakup));
        }
    } else if (prototype_attached_body) {
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


