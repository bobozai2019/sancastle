shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;

// T07 G01/G02: make depth, flow and foam readable from the normal view, with no
// lighting pass and no physics writes. Everything here is a pure function of the
// state textures the simulation already publishes.

uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D momentum_x_state : filter_nearest, repeat_disable;
uniform sampler2D momentum_z_state : filter_nearest, repeat_disable;
uniform sampler2D foam_state : filter_linear, repeat_disable;
uniform sampler2D prototype_scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D prototype_scene_depth : hint_depth_texture, repeat_disable, filter_nearest;

uniform float wet_epsilon_m = 0.001;
uniform float water_surface_bias_m = 0.006;
uniform int debug_mode = 0;

// Beer-Lambert depth cue: the bed stops showing through after roughly this much
// water, which is what separates a shallow margin from the channel.
uniform float extinction_depth_m = 0.09;
uniform vec3 shallow_tint = vec3(0.36, 0.71, 0.76);
uniform vec3 deep_tint = vec3(0.045, 0.24, 0.50);
uniform vec3 foam_tint = vec3(0.93, 0.96, 0.97);

// Foam rides on moving shallow water, not on the waterline itself. Anchoring it
// to a depth threshold alone would paint a permanent white ring around every
// shoreline, which the acceptance forbids; requiring speed makes it appear and
// disappear with the flow.
//
// Thresholds come from the measured distribution in this scene at tick 600:
// wet cells 17969, max depth 0.287 m, depth-averaged speed p50 0.336,
// p90 0.715, p99 1.029, max 1.471 m/s. Foam starts above p90 so it marks riffles
// rather than the whole channel.
uniform float foam_speed_m_s = 0.85;
uniform float foam_depth_m = 0.05;
uniform float foam_strength = 0.55;

// Flow ripples: streaks aligned with the local momentum, drifting with TIME.
uniform float ripple_frequency = 150.0;
uniform float ripple_speed = 2.6;
uniform float ripple_strength = 0.045;
// A negative value preserves the interactive preview's real-time animation.
uniform float visual_time_s = -1.0;
uniform bool phase2_optics = false;
uniform bool phase2_foam = false;
uniform bool display_reconstruction = false;
uniform bool radial_shore = false;
uniform bool shoreline_debug = false;
uniform bool midpoint_clip = false;
uniform bool use_detail_normals = true;
uniform bool use_specular = true;
uniform bool use_caustics = true;
// W07 isolated A/B trial: reconstruct the actual simulated free-surface slope.
uniform bool prototype_eta_normals = false;
uniform bool prototype_screen_optics = false;
uniform float prototype_refraction_scale = 0.0;
uniform bool prototype_depth_guard = true;
uniform float prototype_crest_height_m = 0.0;
uniform float prototype_crest_shore_depth_m = 0.0;
uniform float prototype_curl_forward_m = 0.0;
uniform bool prototype_crest_white_face = false;
uniform bool prototype_crest_span_smoothing = false;
uniform bool prototype_crest_depth_gate_bypass = false;
uniform bool prototype_geometry_silhouette = false;
uniform float prototype_geometry_alpha = 1.0;
uniform bool prototype_geometry_keep_alpha = false;
uniform bool prototype_geometry_keep_color = false;
uniform bool prototype_crest_fragment_foam = false;
uniform bool prototype_irregular_foam = false;
uniform bool prototype_broad_crest = false;
uniform bool prototype_shared_bed_triangles = false;
varying float prototype_crest_lift_v;
uniform float phase2_extinction_m = 0.11;
uniform vec3 phase2_shallow_tint = vec3(0.04, 0.72, 0.69);
uniform vec3 phase2_deep_tint = vec3(0.02, 0.29, 0.37);

vec4 state_cell(ivec2 cell) {
    ivec2 safe_cell = clamp(cell, ivec2(0), ivec2(255));
    float bed = texelFetch(rock_state, safe_cell, 0).r +
        texelFetch(sand_state, safe_cell, 0).r;
    float depth = max(texelFetch(water_state, safe_cell, 0).r, 0.0);
    float wet = step(wet_epsilon_m, depth);
    return vec4(bed, (bed + depth) * wet, wet, depth);
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
    blend = blend * blend * (vec2(3.0) - vec2(2.0) * blend);
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
        depth = min(max(wet_eta - combined.x, 0.0) * combined.z, local_max);
    }
    return vec3(combined.x, depth, combined.z);
}

float prototype_view_distance(vec2 screen_uv, mat4 inv_projection) {
    float raw_depth = textureLod(prototype_scene_depth, screen_uv, 0.0).r;
    vec4 view_position = inv_projection *
        vec4(screen_uv * 2.0 - 1.0, raw_depth, 1.0);
    return -view_position.z / view_position.w;
}

float prototype_crest(vec2 uv, float water_depth) {
    if (prototype_crest_height_m <= 0.0) {
        return 0.0;
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

float prototype_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float prototype_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 blend = fract(p);
    blend = blend * blend * (vec2(3.0) - 2.0 * blend);
    return mix(mix(prototype_hash(cell), prototype_hash(cell + vec2(1.0, 0.0)), blend.x),
        mix(prototype_hash(cell + vec2(0.0, 1.0)),
            prototype_hash(cell + vec2(1.0, 1.0)), blend.x), blend.y);
}

float prototype_near_wet_eta(vec2 uv, float fallback) {
    ivec2 center = ivec2(round(uv * 256.0 - vec2(0.5)));
    float eta_sum = 0.0;
    float weight_sum = 0.0;
    for (int dz = -1; dz <= 1; dz++) {
        for (int dx = -1; dx <= 1; dx++) {
            ivec2 cell = clamp(center + ivec2(dx, dz), ivec2(0), ivec2(255));
            float depth = max(texelFetch(water_state, cell, 0).r, 0.0);
            if (depth > wet_epsilon_m) {
                float bed = texelFetch(rock_state, cell, 0).r +
                    texelFetch(sand_state, cell, 0).r;
                float cell_distance = length(uv * 256.0 - vec2(cell) - vec2(0.5));
                float weight = 1.0 / (0.2 + cell_distance * cell_distance);
                eta_sum += (bed + depth) * weight;
                weight_sum += weight;
            }
        }
    }
    return weight_sum > 0.0 ? eta_sum / weight_sum : fallback;
}
void vertex() {
    vec3 surface = display_surface(UV);
    float crest_lift = prototype_crest(UV, surface.y);
    prototype_crest_lift_v = crest_lift;
    VERTEX.y = surface.x + surface.y + water_surface_bias_m + crest_lift;
    if (surface.z < 0.999 && surface.y <= 0.035) {
        VERTEX.y = prototype_near_wet_eta(UV, VERTEX.y) +
            water_surface_bias_m;
    }
    if (prototype_curl_forward_m > 0.0 && prototype_crest_height_m > 0.0) {
        float crest_fraction = clamp(crest_lift / prototype_crest_height_m, 0.0, 1.0);
        // Keep the display-only lip away from nearly dry cells and sand toes.
        float deep_enough = smoothstep(0.05, 0.12, surface.y);
        VERTEX.x += prototype_curl_forward_m * crest_fraction * crest_fraction *
            deep_enough;
    }
    if (prototype_eta_normals && surface.y > wet_epsilon_m) {
        vec2 step_uv = vec2(1.0 / 256.0, 0.0);
        vec3 left = display_surface(clamp(UV - step_uv, vec2(0.0), vec2(1.0)));
        vec3 right = display_surface(clamp(UV + step_uv, vec2(0.0), vec2(1.0)));
        vec3 back = display_surface(clamp(UV - step_uv.yx, vec2(0.0), vec2(1.0)));
        vec3 front = display_surface(clamp(UV + step_uv.yx, vec2(0.0), vec2(1.0)));
        float eta = surface.x + surface.y + prototype_crest(UV, surface.y);
        float eta_left = left.y > wet_epsilon_m ?
            left.x + left.y + prototype_crest(UV - step_uv, left.y) : eta;
        float eta_right = right.y > wet_epsilon_m ?
            right.x + right.y + prototype_crest(UV + step_uv, right.y) : eta;
        float eta_back = back.y > wet_epsilon_m ?
            back.x + back.y + prototype_crest(UV - step_uv.yx, back.y) : eta;
        float eta_front = front.y > wet_epsilon_m ?
            front.x + front.y + prototype_crest(UV + step_uv.yx, front.y) : eta;
        NORMAL = normalize(vec3(-(eta_right - eta_left) / 0.25, 1.0,
            -(eta_front - eta_back) / 0.25));
    }
}

void fragment() {
    if (debug_mode != 0) {
        discard;
    }
    vec3 surface = display_surface(UV);
    float depth = surface.y;
    if (depth <= wet_epsilon_m) {
        discard;
    }
    vec2 flow = vec2(texture(momentum_x_state, UV).r, texture(momentum_z_state, UV).r)
        / max(depth, 0.001);
    float speed = length(flow);

    if (shoreline_debug) {
        ALBEDO = vec3(1.0);
        ALPHA = 1.0;
    } else if (prototype_screen_optics) {
        // Isolated screen-space transmission/refraction route. The scene copy
        // contains the opaque sand and depth; transparent objects are excluded.
        float t = visual_time_s >= 0.0 ? visual_time_s : TIME;
        vec2 uv_m = UV * 32.0;
        float attenuation = smoothstep(0.008, 0.065, depth);
        vec2 detail = vec2(
            sin(uv_m.x * 3.1 + uv_m.y * 1.7 - t * 1.2),
            cos(uv_m.y * 2.8 - uv_m.x * 1.4 - t * 0.9)) *
            0.075 * attenuation;
        vec3 detail_view = mat3(VIEW_MATRIX) *
            (MODEL_NORMAL_MATRIX * vec3(detail.x, 0.0, detail.y));
        vec3 n = normalize(NORMAL + detail_view);
        float surface_distance = -VERTEX.z;
        float original_distance = prototype_view_distance(SCREEN_UV,
            INV_PROJECTION_MATRIX);
        vec2 offset = n.xy * prototype_refraction_scale *
            smoothstep(0.005, 0.20, depth) *
            smoothstep(0.005, 0.08, original_distance - surface_distance);
        vec2 candidate_uv = clamp(SCREEN_UV + offset,
            vec2(0.001), vec2(0.999));
        float candidate_distance = prototype_view_distance(candidate_uv,
            INV_PROJECTION_MATRIX);
        vec2 sampled_uv = candidate_uv;
        if (prototype_depth_guard && candidate_distance <= surface_distance + 0.005) {
            sampled_uv = SCREEN_UV;
        }
        vec3 bed_color = textureLod(prototype_scene_color, sampled_uv, 0.0).rgb;
        float path_length = depth / max(abs(dot(normalize(VIEW), n)), 0.25);
        float transmission = exp(-path_length / phase2_extinction_m);
        vec3 scatter = mix(phase2_shallow_tint, phase2_deep_tint,
            smoothstep(0.02, 0.30, depth));
        vec3 transmitted = bed_color * transmission + scatter * (1.0 - transmission);
        float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), n), 0.0, 1.0), 5.0);
        // This is only a sky-color proxy. A real reflected scene remains unproved.
        ALBEDO = mix(transmitted, vec3(0.55, 0.75, 0.86),
            0.025 + 0.42 * fresnel);
        ALPHA = smoothstep(wet_epsilon_m, 0.015, depth);
        if (display_reconstruction) {
            ALPHA *= smoothstep(0.0, 0.8, surface.z);
        }
    } else if (phase2_optics) {
        float t = visual_time_s >= 0.0 ? visual_time_s : TIME;
        vec2 uv_m = UV * 32.0;
        vec2 flow_direction = normalize(flow + vec2(0.001, 0.0));
        float attenuation = smoothstep(0.008, 0.065, depth);
        vec2 detail = vec2(0.0);
        if (use_detail_normals) {
            detail = vec2(
                sin(uv_m.x * 3.1 + uv_m.y * 1.7 - t * 1.2),
                cos(uv_m.y * 2.8 - uv_m.x * 1.4 - t * 0.9)) * 0.075 * attenuation;
            detail += flow_direction * sin(dot(uv_m, flow_direction) * 7.0 - t * 2.0)
                * 0.025 * attenuation;
        }
        vec3 n = normalize(vec3(detail.x, detail.y, 1.0));
        if (prototype_eta_normals) {
            vec3 detail_view = mat3(VIEW_MATRIX) *
                (MODEL_NORMAL_MATRIX * vec3(detail.x, 0.0, detail.y));
            n = normalize(NORMAL + detail_view);
        }
        float transmission = exp(-depth / phase2_extinction_m);
        float depth_fraction = 1.0 - transmission;
        vec3 scatter = mix(phase2_shallow_tint, phase2_deep_tint,
            smoothstep(0.02, 0.30, depth));
        float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), n), 0.0, 1.0), 5.0);
        float reflection = 0.04 + 0.34 * fresnel;
        if (!use_specular) {
            reflection = 0.0;
        }
        float glint = use_specular ? pow(max(0.0, dot(n,
            normalize(vec3(-0.10, 0.10, 0.99)))), 28.0) * 0.12 * attenuation : 0.0;
        ALBEDO = mix(scatter, vec3(0.53, 0.78, 0.79), reflection) + vec3(glint);
        ALPHA = clamp(depth_fraction * (1.0 - reflection) + reflection * 0.75,
            0.0, 0.95) * smoothstep(wet_epsilon_m, 0.018, depth);
        if (phase2_foam) {
            float coverage = clamp(texture(foam_state, UV).r, 0.0, 1.0);
            if (prototype_broad_crest) {
                vec2 step_uv = vec2(1.0 / 256.0, 0.0);
                float near_left = textureLod(foam_state,
                    clamp(UV - step_uv * 2.0, vec2(0.0), vec2(1.0)), 0.0).r;
                float near_right = textureLod(foam_state,
                    clamp(UV + step_uv * 2.0, vec2(0.0), vec2(1.0)), 0.0).r;
                float outer_left = textureLod(foam_state,
                    clamp(UV - step_uv * 4.0, vec2(0.0), vec2(1.0)), 0.0).r;
                float outer_right = textureLod(foam_state,
                    clamp(UV + step_uv * 4.0, vec2(0.0), vec2(1.0)), 0.0).r;
                coverage = max(coverage, max(0.65 * max(near_left, near_right),
                    0.38 * max(outer_left, outer_right)));
            }
            float breakup = 0.5 + 0.5 * sin(uv_m.x * 7.3 +
                1.8 * sin(uv_m.y * 4.7 + t * 0.4)) *
                sin(uv_m.y * 8.1 - uv_m.x * 1.9 - t * 0.3);
            float whitewater = smoothstep(0.13, 0.62, coverage * breakup) *
                smoothstep(wet_epsilon_m, 0.012, depth);
            if (prototype_irregular_foam) {
                float large = prototype_noise(uv_m * 1.6);
                float small = prototype_noise(uv_m * 5.2 + vec2(19.3, -7.1));
                float fragments = mix(large, small, 0.65);
                whitewater = smoothstep(0.12, 0.52, coverage) *
                    (0.35 + 0.65 * smoothstep(0.22, 0.76, fragments)) *
                    smoothstep(wet_epsilon_m, 0.012, depth);
            }
            if (prototype_crest_white_face && prototype_crest_height_m > 0.0) {
                float raised_face = smoothstep(0.025, 0.17,
                    prototype_crest_lift_v) * smoothstep(0.035, 0.10, depth);
                if (prototype_crest_fragment_foam) {
                    raised_face = smoothstep(0.08, 0.36, coverage) *
                        smoothstep(0.035, 0.10, depth);
                }
                float irregular_edge = 0.72 + 0.28 * prototype_noise(
                    uv_m * 3.7 + vec2(5.1, -13.4));
                float face_foam = prototype_crest_span_smoothing ?
                    smoothstep(0.04, 0.30, coverage) : 1.0;
                whitewater = max(whitewater,
                    raised_face * irregular_edge * face_foam);
            }
            ALBEDO = mix(ALBEDO, foam_tint,
                whitewater * (prototype_crest_white_face ? 0.94 : 0.78));
            ALPHA = mix(ALPHA,
                prototype_crest_white_face ? 0.98 : 0.93, whitewater);
        }
        if (display_reconstruction) {
            ALPHA *= smoothstep(0.0, 0.8, surface.z);
        }
    } else {

    float optical = 1.0 - exp(-depth / extinction_depth_m);
    vec3 color = mix(shallow_tint, deep_tint, optical);

    // Streaks travel along the flow direction and fade out where the water is
    // nearly still, so ponded water reads smooth instead of patterned.
    float phase = dot(UV, normalize(flow + vec2(1e-5))) * ripple_frequency;
    float ripple = sin(phase - (visual_time_s >= 0.0 ? visual_time_s : TIME) * ripple_speed);
    float moving_fraction = clamp((speed - 0.15) * 2.0, 0.0, 1.0);
    color *= 1.0 + ripple * ripple_strength * moving_fraction;

    float moving = smoothstep(foam_speed_m_s, foam_speed_m_s * 2.5, speed);
    float thin = 1.0 - smoothstep(foam_depth_m, foam_depth_m * 3.0, depth);
    float foam = clamp(moving * thin, 0.0, 1.0) * foam_strength;
    color = mix(color, foam_tint, foam);

    ALBEDO = color;
    // Shallow water stays translucent so the bed reads through; deep water closes
    // up so no field of bare sand shows through as a blue patch.
    //
    // The surface fades in over the first few centimetres of depth. Without that
    // the mesh's facets stay fully visible where the water is nearly edge-on,
    // which at a grazing angle reads as a staircase of quads along the bank.
    float shoreline_fade = smoothstep(wet_epsilon_m, 0.035, depth);
    ALPHA = clamp((mix(0.30, 0.94, optical) + foam * 0.05) * shoreline_fade, 0.0, 1.0);
    }
    if (prototype_geometry_silhouette) {
        if (!prototype_geometry_keep_color) {
            ALBEDO = vec3(0.92, 0.12, 0.16);
        }
        if (!prototype_geometry_keep_alpha) {
            ALPHA = prototype_geometry_alpha;
        }
    }
}

