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

uniform sampler2D foam_previous_state : filter_nearest, repeat_disable;
uniform sampler2D rise_front_state : filter_linear, repeat_disable;
uniform float water_surface_bias_m = 0.006;
uniform bool display_reconstruction = false;
uniform bool radial_shore = false;
uniform bool prototype_shore_unscaled_depth = false;
uniform bool prototype_shore_linear_weights = false;
uniform float prototype_render_grid_size = 512.0;
uniform bool midpoint_clip = false;
uniform float prototype_crest_height_m = 0.0;
uniform float prototype_local_back_cells = 7.5;
uniform float prototype_local_face_cells = 1.8;
uniform float prototype_local_lift_depth_scale = 1.5;
uniform float prototype_crest_shore_depth_m = 0.0;
uniform float prototype_curl_forward_m = 0.0;
uniform float prototype_local_overturn_m = 0.0;
uniform bool prototype_crest_span_smoothing = false;
uniform bool prototype_crest_depth_gate_bypass = false;
uniform bool prototype_front_face_source_gate = false;
uniform bool prototype_front_face_source_started = false;
uniform bool prototype_broad_crest = false;
uniform bool prototype_shared_bed_triangles = false;
uniform bool prototype_rise_crest = false;
uniform bool prototype_use_front_field = false;
uniform bool prototype_use_local_front = false;
uniform bool natural_contact_shared_surface = false;
uniform float natural_contact_separation_m = 0.001;

vec4 state_cell(ivec2 cell) {
    ivec2 safe_cell = clamp(cell, ivec2(0), ivec2(255));
    float bed = texelFetch(rock_state, safe_cell, 0).r +
        texelFetch(sand_state, safe_cell, 0).r;
    float depth = max(texelFetch(water_state, safe_cell, 0).r, 0.0);
    float wet = step(wet_epsilon_m, depth);
    return vec4(bed, (bed + depth) * wet, wet, depth);
}

float coupled_bed_triangle_at(vec2 uv) {
    vec2 cell = uv * 256.0 - vec2(0.5);
    ivec2 low = ivec2(floor(cell));
    vec2 weight = fract(cell);
    float v00 = state_cell(low).x;
    float v10 = state_cell(low + ivec2(1, 0)).x;
    float v01 = state_cell(low + ivec2(0, 1)).x;
    float v11 = state_cell(low + ivec2(1, 1)).x;
    // Match reference_coupled_bed.gdshader's analytic texture-cell bed_at.
    if (weight.x + weight.y <= 1.0) {
        return v00 + weight.x * (v10 - v00) + weight.y * (v01 - v00);
    }
    return v11 + (1.0 - weight.x) * (v01 - v11) +
        (1.0 - weight.y) * (v10 - v11);
}

float coupled_bed_render_mesh_at(vec2 uv) {
    // Match gpu_water_preview.gd's display mesh and the terrain vertex shader.
    vec2 cell = uv * prototype_render_grid_size - vec2(0.5);
    ivec2 low = ivec2(floor(cell));
    vec2 weight = fract(cell);
    vec2 uv00 = (vec2(low) + vec2(0.5)) / prototype_render_grid_size;
    vec2 step_uv = vec2(1.0 / prototype_render_grid_size);
    float v00 = coupled_bed_triangle_at(uv00);
    float v10 = coupled_bed_triangle_at(uv00 + vec2(step_uv.x, 0.0));
    float v01 = coupled_bed_triangle_at(uv00 + vec2(0.0, step_uv.y));
    float v11 = coupled_bed_triangle_at(uv00 + step_uv);
    // _make_grid_mesh uses the v00->v11 diagonal for its actual triangles.
    if (weight.y <= weight.x) {
        return v00 + weight.x * (v10 - v00) +
            weight.y * (v11 - v10);
    }
    return v00 + weight.y * (v01 - v00) +
        weight.x * (v11 - v01);
}

vec3 display_surface(vec2 uv) {
    if (!display_reconstruction) {
        float bed = textureLod(rock_state, uv, 0.0).r +
            textureLod(sand_state, uv, 0.0).r;
        float depth = textureLod(water_state, uv, 0.0).r;
        return vec3(bed, depth, step(wet_epsilon_m, depth));
    }
    vec2 cell = uv * 256.0 - vec2(0.5);
    ivec2 low = ivec2(floor(cell));
    vec2 cell_fraction = fract(cell);
    vec2 blend = cell_fraction;
    if (!prototype_shore_linear_weights) {
        blend = blend * blend * (vec2(3.0) - vec2(2.0) * blend);
    }
    vec4 s00 = state_cell(low);
    vec4 s10 = state_cell(low + ivec2(1, 0));
    vec4 s01 = state_cell(low + ivec2(0, 1));
    vec4 s11 = state_cell(low + ivec2(1, 1));
    vec4 combined = mix(mix(s00, s10, blend.x), mix(s01, s11, blend.x), blend.y);
    if (prototype_shared_bed_triangles) {
        // Match reference_coupled_bed.gdshader's piecewise-linear bed surface.
        // Both meshes then intersect the same reconstructed height within a cell.
        if (cell_fraction.x + cell_fraction.y <= 1.0) {
            combined.x = s00.x + cell_fraction.x * (s10.x - s00.x) +
                cell_fraction.y * (s01.x - s00.x);
        } else {
            combined.x = s11.x + (1.0 - cell_fraction.x) * (s01.x - s11.x) +
                (1.0 - cell_fraction.y) * (s10.x - s11.x);
        }
    }
    float depth = 0.0;
    if (midpoint_clip && combined.z < 0.5) {
        return vec3(combined.x, 0.0, combined.z);
    }
    if (radial_shore) {
        ivec2 nearest = ivec2(round(cell));
        float nearest_wet = 10.0;
        float eta_sum = 0.0;
        float weight_sum = 0.0;
        float local_max = 0.0;
        for (int dz = -1; dz <= 1; dz++) {
            for (int dx = -1; dx <= 1; dx++) {
                ivec2 sample_cell = nearest + ivec2(dx, dz);
                vec4 state = state_cell(sample_cell);
                if (state.z > 0.0) {
                    float distance_cells = length(cell - vec2(sample_cell));
                    nearest_wet = min(nearest_wet, distance_cells);
                    float weight = exp(-distance_cells * distance_cells * 1.5);
                    eta_sum += state.y * weight;
                    weight_sum += weight;
                    local_max = max(local_max, state.w);
                }
            }
        }
        if (weight_sum > 0.0) {
            float coverage = 1.0 - smoothstep(0.45, 1.05, nearest_wet);
            depth = min(max(eta_sum / weight_sum - combined.x, 0.0) * coverage,
                local_max);
            return vec3(combined.x, depth, coverage);
        }
        return vec3(combined.x, 0.0, 0.0);
    }
    if (combined.z > 0.0) {
        // Wet cells share an eta; the continuously reconstructed bed then
        // determines the intersection. The wet fraction confines the frontier
        // to the adjoining half-cell instead of flooding dry neighbours.
        float wet_eta = combined.y / combined.z;
        float local_max = max(max(s00.w, s10.w), max(s01.w, s11.w));
        depth = min(max(wet_eta - combined.x, 0.0) *
            (prototype_shore_unscaled_depth ? 1.0 : combined.z), local_max);
    }
    return vec3(combined.x, depth, combined.z);
}

float prototype_crest(vec2 uv, float water_depth) {
    if (prototype_crest_height_m <= 0.0 ||
            (prototype_front_face_source_gate &&
                !prototype_front_face_source_started)) {
        return 0.0;
    }
    if (prototype_use_local_front) {
        vec2 front = textureLod(local_front_state, uv, 0.0).rg;
        float distance_cells = uv.x * 256.0 - 0.5 - front.x;
        float back_shoulder = smoothstep(-prototype_local_back_cells, -1.0,
            distance_cells);
        float advancing_face = 1.0 - smoothstep(0.0,
            prototype_local_face_cells,
            distance_cells);
        float lift = prototype_crest_height_m *
            smoothstep(0.0012, 0.0045, front.y) *
            back_shoulder * advancing_face *
            smoothstep(0.012, 0.065, water_depth);
        return min(lift, max(water_depth, 0.0) *
            prototype_local_lift_depth_scale);
    }
    if (prototype_rise_crest) {
        if (prototype_use_front_field) {
            vec2 front = textureLod(rise_front_state, vec2(uv.y, 0.5), 0.0).rg;
            float cell_x = uv.x * 256.0 - 0.5;
            // Back shoulder rises over 11 cells; the advancing face falls in
            // two cells. The existing Gaussian has equal slopes on both sides.
            float distance_cells = cell_x - front.x;
            float back_shoulder = smoothstep(-12.0, -1.0, distance_cells);
            float advancing_face = 1.0 - smoothstep(0.0, 2.0, distance_cells);
            float shape = back_shoulder * advancing_face;
            return prototype_crest_height_m *
                smoothstep(0.0025, 0.0050, front.y) * shape *
                smoothstep(0.012, 0.065, water_depth);
        }
        float strongest = 0.0;
        for (int dz = -2; dz <= 2; dz += 2) {
            for (int dx = -2; dx <= 2; dx++) {
                vec2 p = clamp(uv + vec2(float(dx), float(dz)) / 256.0,
                    vec2(0.0), vec2(1.0));
                float current_depth = max(textureLod(water_state, p, 0.0).r, 0.0);
                float earlier_depth = max(textureLod(foam_previous_state, p, 0.0).g, 0.0);
                float weight = dx == 0 && dz == 0 ? 1.0 : 0.75;
                strongest = max(strongest, weight *
                    max(current_depth - earlier_depth, 0.0) *
                    smoothstep(0.01, 0.04, current_depth));
            }
        }
        return prototype_crest_height_m *
            smoothstep(0.0025, 0.0050, strongest) *
            smoothstep(0.012, 0.065, water_depth);
    }
    vec2 step_uv = vec2(1.0 / 256.0, 0.0);
    float center = textureLod(foam_state, uv, 0.0).r;
    float left = textureLod(foam_state,
        clamp(uv - step_uv, vec2(0.0), vec2(1.0)), 0.0).r;
    float right = textureLod(foam_state,
        clamp(uv + step_uv, vec2(0.0), vec2(1.0)), 0.0).r;
    float coverage = max(center, 0.6 * max(left, right));
    if (prototype_crest_span_smoothing) {
        vec2 span_step = step_uv.yx;
        float near_back = textureLod(foam_state,
            clamp(uv - span_step, vec2(0.0), vec2(1.0)), 0.0).r;
        float near_front = textureLod(foam_state,
            clamp(uv + span_step, vec2(0.0), vec2(1.0)), 0.0).r;
        float far_back = textureLod(foam_state,
            clamp(uv - 2.0 * span_step, vec2(0.0), vec2(1.0)), 0.0).r;
        float far_front = textureLod(foam_state,
            clamp(uv + 2.0 * span_step, vec2(0.0), vec2(1.0)), 0.0).r;
        coverage = max(coverage, max(0.8 * max(near_back, near_front),
            0.55 * max(far_back, far_front)));
    }
    if (prototype_broad_crest) {
        vec2 outer_step = step_uv * 3.0;
        float outer_left = textureLod(foam_state,
            clamp(uv - outer_step, vec2(0.0), vec2(1.0)), 0.0).r;
        float outer_right = textureLod(foam_state,
            clamp(uv + outer_step, vec2(0.0), vec2(1.0)), 0.0).r;
        coverage = max(coverage, 0.42 * max(outer_left, outer_right));
    }
    float shore_factor = prototype_crest_shore_depth_m > 0.0 ?
        smoothstep(prototype_crest_shore_depth_m,
            prototype_crest_shore_depth_m + 0.08, water_depth) : 1.0;
    float depth_factor = prototype_crest_depth_gate_bypass ?
        step(wet_epsilon_m, water_depth) :
        smoothstep(0.012, 0.08, water_depth);
    return prototype_crest_height_m * smoothstep(0.04, 0.45, coverage) *
        depth_factor * shore_factor;
}

void vertex() {
    if (natural_contact_shared_surface) {
    vec3 surface = display_surface(UV);
    float crest_lift = prototype_crest(UV, surface.y);
    VERTEX.y = surface.x + surface.y + water_surface_bias_m + crest_lift;
    if (prototype_curl_forward_m > 0.0 && prototype_crest_height_m > 0.0) {
        float crest_fraction = clamp(crest_lift / prototype_crest_height_m, 0.0, 1.0);
        // Keep the display-only lip away from nearly dry cells and sand toes.
        float deep_enough = smoothstep(0.05, 0.12, surface.y);
        VERTEX.x += prototype_curl_forward_m * crest_fraction * crest_fraction *
            deep_enough;
    }
    if (prototype_local_overturn_m > 0.0 && prototype_use_local_front &&
            prototype_crest_height_m > 0.0 && surface.y > 0.04) {
        vec2 front = textureLod(local_front_state, UV, 0.0).rg;
        float distance_cells = UV.x * 256.0 - 0.5 - front.x;
        float crown = smoothstep(-2.0, -0.35, distance_cells) *
            (1.0 - smoothstep(0.0, 1.6, distance_cells));
        float lift_gate = smoothstep(0.03, 0.20, crest_lift);
        float dry_limit_m = 0.60;
        for (int step_cells = 1; step_cells <= 5; step_cells++) {
            vec2 ahead = clamp(UV + vec2(float(step_cells) / 256.0, 0.0),
                vec2(0.0), vec2(1.0));
            if (textureLod(water_state, ahead, 0.0).r < 0.01) {
                dry_limit_m = max(0.0, float(step_cells - 1) * 0.125);
                break;
            }
        }
        float requested = prototype_local_overturn_m * crown * lift_gate;
        VERTEX.x += min(requested, dry_limit_m);
    }
    VERTEX.y += natural_contact_separation_m;

    } else {
        vec3 surface=display_surface(UV);
        VERTEX.y=surface.x+surface.y+surface_offset_m;
    }
}

void fragment() {
    if (!enabled || !natural_contact_enabled) {
        discard;
    }
    vec3 surface = display_surface(UV);
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
