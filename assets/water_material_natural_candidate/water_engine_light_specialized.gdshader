shader_type spatial;
render_mode ambient_light_disabled, cull_disabled, blend_mix, depth_draw_always;

// T07 G01/G02: make depth, flow and foam readable from the normal view, with no
// lighting pass and no physics writes. Everything here is a pure function of the
// state textures the simulation already publishes.

uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D momentum_x_state : filter_nearest, repeat_disable;
uniform sampler2D momentum_z_state : filter_nearest, repeat_disable;
uniform sampler2D foam_state : filter_linear, repeat_disable;
uniform sampler2D foam_previous_state : filter_nearest, repeat_disable;
uniform sampler2D rise_front_state : filter_linear, repeat_disable;
uniform sampler2D local_front_state : filter_linear, repeat_disable;
uniform sampler2D contact_history_state : filter_linear, repeat_disable;
uniform sampler2D prototype_scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D prototype_scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D prototype_planar_reflection : filter_linear, repeat_disable;
uniform sampler2D prototype_caustic_pattern : filter_linear_mipmap, repeat_enable;

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
uniform float test1_whitewater_gain = 1.0;

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
uniform bool prototype_shore_unscaled_depth = false;
uniform bool prototype_shore_linear_weights = false;
uniform bool shoreline_debug = false;
uniform bool prototype_contact_alpha_debug = false;
uniform bool prototype_shore_source_debug = false;
uniform bool prototype_contact_foam_source_debug = false;
uniform bool prototype_contact_foam_candidate = false;
uniform bool prototype_contact_front_gate = false;
uniform bool prototype_contact_wide_band = false;
uniform bool prototype_contact_relaxed_front_gate = false;
uniform bool prototype_contact_history_gate = false;
uniform bool prototype_contact_foam_spread = false;
uniform bool prototype_contact_scene_gap_gate = false;
uniform bool prototype_contact_independent_history_gate = false;
uniform bool prototype_contact_depth_debug = false;
uniform bool prototype_contact_height_debug = false;
uniform bool prototype_vertex_fragment_delta_debug = false;
uniform bool prototype_visible_bed_height_debug = false;
uniform bool prototype_contact_residual_debug = false;
uniform float prototype_render_grid_size = 512.0;
uniform bool midpoint_clip = false;
uniform bool use_detail_normals = true;
// Normal-only candidate v1: macro geometry is unchanged.
uniform int natural_normal_mode = 1; // 0 off, 1 legacy, 2 texture
uniform sampler2D natural_normal_texture : filter_linear_mipmap, repeat_enable;
uniform vec4 natural_layer0 = vec4(0.18, 0.035, 0.06, 0.0);
uniform vec4 natural_layer1 = vec4(0.47, -0.022, 0.025, 0.0);
uniform vec2 natural_direction0 = vec2(1.0, 0.0);
uniform vec2 natural_direction1 = vec2(0.6, 0.8);
uniform int natural_normal_debug = 0;
uniform bool use_specular = true;
uniform bool use_caustics = true;
// W07 isolated A/B trial: reconstruct the actual simulated free-surface slope.
uniform bool prototype_eta_normals = false;
uniform bool prototype_eta_normal_debug = false;
uniform bool prototype_eta_normal_space_debug = false;
uniform bool prototype_eta_light_space_debug = false;
uniform vec3 prototype_light_direction_world = vec3(-0.10, 0.10, 0.99);
uniform bool prototype_screen_optics = false;
uniform bool prototype_screen_world_glint = false;
uniform bool natural_glint_enabled = true;
uniform float natural_glint_gain = 0.32;
uniform float natural_glint_exponent = 42.0;
uniform float natural_scatter_direct_fraction = 0.45;
uniform float natural_foam_direct_fraction = 0.50;
uniform int natural_lighting_debug = 0;
varying vec2 natural_optical_weights;
varying float natural_water_depth;
uniform bool prototype_screen_sky_gradient = false;
uniform bool prototype_optical_shallow_preserve = false;
uniform float prototype_screen_deep_scatter_scale = 1.0;
uniform float prototype_screen_sky_reflection_scale = 1.0;
uniform bool prototype_screen_fresnel_debug = false;
uniform bool prototype_screen_abs_fresnel = false;
uniform bool prototype_screen_face_normal = false;
uniform bool prototype_screen_scene_reflection = false;
uniform bool prototype_screen_reflection_debug = false;
uniform bool prototype_screen_bed_only = false;
uniform float prototype_shallow_extinction_m = 0.11;
uniform bool prototype_planar_reflection_enabled = false;
uniform bool prototype_planar_reflection_debug = false;
uniform bool prototype_planar_reflection_projected = false;
uniform float prototype_planar_reflection_softness_px = 0.0;
uniform mat4 prototype_planar_view_projection;
// Diagnostic only: label visible water pixels by the same reconstructed depth
// used by the optical branches. Red is 0.02-0.08m; blue is >=0.20m.
uniform bool prototype_depth_bands = false;
uniform bool prototype_depth_gray_debug = false;
// Diagnostic only: exact vertical-depth bins for W10 optical decomposition.
uniform bool prototype_depth_layers_debug = false;
uniform float prototype_refraction_scale = 0.0;
uniform bool prototype_depth_guard = true;
uniform bool prototype_legacy_edge_clamp = false;
uniform bool prototype_refraction_fallback_debug = false;
uniform float prototype_crest_height_m = 0.0;
uniform float prototype_local_back_cells = 7.5;
uniform float prototype_local_face_cells = 1.8;
uniform float prototype_local_lift_depth_scale = 1.5;
uniform float prototype_crest_shore_depth_m = 0.0;
uniform float prototype_curl_forward_m = 0.0;
uniform float prototype_local_overturn_m = 0.0;
uniform bool prototype_crest_white_face = false;
uniform bool prototype_crest_span_smoothing = false;
uniform bool prototype_crest_depth_gate_bypass = false;
uniform bool prototype_geometry_silhouette = false;
uniform float prototype_geometry_alpha = 1.0;
uniform bool prototype_geometry_keep_alpha = false;
uniform bool prototype_geometry_keep_color = false;
uniform bool prototype_crest_fragment_foam = false;
uniform bool prototype_crest_broken_core = false;
uniform bool prototype_offshore_core = false;
uniform bool prototype_offshore_core_broken = false;
uniform bool prototype_offshore_core_crown = false;
uniform bool prototype_offshore_core_source_started = false;
uniform bool prototype_front_face_rim_tone = false;
uniform bool prototype_front_face_foam_gate = false;
uniform bool prototype_front_face_source_gate = false;
uniform bool prototype_front_face_source_started = false;
uniform bool prototype_irregular_foam = false;
uniform bool prototype_aperiodic_foam = false;
uniform bool prototype_front_foam_blend = false;
uniform bool prototype_front_foam_ribbon = false;
uniform bool prototype_foam_flow_detail = false;
uniform bool prototype_broad_crest = false;
uniform bool prototype_shared_bed_triangles = false;
uniform bool prototype_rise_crest = false;
uniform bool prototype_use_front_field = false;
uniform bool prototype_use_local_front = false;
varying float prototype_crest_lift_v;
varying vec3 prototype_eta_normal_local_v;
uniform float phase2_extinction_m = 0.11;
uniform float prototype_deep_extinction_m = 0.11;
// W11 topdown diagnostic: restore an explicitly bed-anchored bright-line
// component after deep-water transmission without changing diffuse scattering.
uniform float prototype_caustic_recovery_gain = 0.0;
uniform float prototype_caustic_recovery_uv_scale = 1.0;
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

float prototype_view_distance(vec2 screen_uv, mat4 inv_projection) {
    float raw_depth = textureLod(prototype_scene_depth, screen_uv, 0.0).r;
    vec4 view_position = inv_projection *
        vec4(screen_uv * 2.0 - 1.0, raw_depth, 1.0);
    return -view_position.z / view_position.w;
}

vec4 prototype_reflected_scene(vec3 view_position, vec3 visible_normal,
        vec3 view_direction, mat4 projection_matrix,
        mat4 inverse_projection_matrix) {
    vec3 ray = normalize(reflect(-view_direction, visible_normal));
    vec3 origin = view_position + visible_normal * 0.025;
    for (int step_index = 0; step_index < 12; step_index++) {
        float distance_m = 0.15 + 0.25 * float(step_index) +
            0.06 * float(step_index * step_index);
        vec3 probe = origin + ray * distance_m;
        if (probe.z >= -0.06) {
            break;
        }
        vec4 clip = projection_matrix * vec4(probe, 1.0);
        if (clip.w <= 0.0) {
            break;
        }
        vec2 screen_uv = clip.xy / clip.w * 0.5 + 0.5;
        if (any(lessThan(screen_uv, vec2(0.005))) ||
                any(greaterThan(screen_uv, vec2(0.995)))) {
            break;
        }
        float scene_distance = prototype_view_distance(screen_uv,
            inverse_projection_matrix);
        float behind_scene = -probe.z - scene_distance;
        if (scene_distance > 0.06 && behind_scene >= 0.0 &&
                behind_scene < 0.35) {
            return vec4(textureLod(prototype_scene_color, screen_uv, 0.0).rgb,
                1.0);
        }
    }
    return vec4(0.55, 0.75, 0.86, 0.0);
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

float prototype_whitewater(vec2 uv, vec2 uv_m, float depth, float t,
        float crest_lift) {
    if (!phase2_foam && !(prototype_use_local_front && prototype_crest_white_face)) {
        return 0.0;
    }
    float coverage = clamp(texture(foam_state, uv).r, 0.0, 1.0);
    if (prototype_broad_crest) {
        vec2 step_uv = vec2(1.0 / 256.0, 0.0);
        float near_left = textureLod(foam_state,
            clamp(uv - step_uv * 2.0, vec2(0.0), vec2(1.0)), 0.0).r;
        float near_right = textureLod(foam_state,
            clamp(uv + step_uv * 2.0, vec2(0.0), vec2(1.0)), 0.0).r;
        float outer_left = textureLod(foam_state,
            clamp(uv - step_uv * 4.0, vec2(0.0), vec2(1.0)), 0.0).r;
        float outer_right = textureLod(foam_state,
            clamp(uv + step_uv * 4.0, vec2(0.0), vec2(1.0)), 0.0).r;
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
    if (prototype_aperiodic_foam) {
        vec2 momentum = vec2(textureLod(momentum_x_state, uv, 0.0).r,
            textureLod(momentum_z_state, uv, 0.0).r);
        vec2 velocity = clamp(momentum / max(depth, 0.02),
            vec2(-2.0), vec2(2.0));
        vec2 position = uv_m - velocity * t * 0.12;
        float warp = prototype_noise(position * 1.4 + vec2(7.1, -3.8));
        float middle = prototype_noise(position * 6.2 +
            vec2(2.4, -5.7) + vec2(warp * 1.8));
        float fine = prototype_noise(position * 17.3 +
            vec2(-11.2, 4.9) + vec2(middle * 2.3));
        float eroded = smoothstep(0.28, 0.72,
            0.42 * middle + 0.58 * fine);
        whitewater = smoothstep(0.13, 0.62,
            coverage * (0.12 + 0.88 * eroded)) *
            smoothstep(wet_epsilon_m, 0.012, depth);
    }
    if (prototype_front_foam_blend) {
        vec2 texel = vec2(1.0 / 256.0, 0.0);
        float along = textureLod(foam_state, clamp(uv - texel,
            vec2(0.0), vec2(1.0)), 0.0).r +
            textureLod(foam_state, clamp(uv + texel,
            vec2(0.0), vec2(1.0)), 0.0).r;
        float across = textureLod(foam_state, clamp(uv - texel.yx,
            vec2(0.0), vec2(1.0)), 0.0).r +
            textureLod(foam_state, clamp(uv + texel.yx,
            vec2(0.0), vec2(1.0)), 0.0).r;
        float soft_coverage = (4.0 * coverage + along + across) / 8.0;
        float irregular_edge = mix(0.72, 1.0, prototype_noise(
            uv_m * 1.1 + vec2(3.7, -11.3)));
        whitewater = smoothstep(0.10, 0.48, soft_coverage) *
            irregular_edge * smoothstep(wet_epsilon_m, 0.012, depth);
    }
    if (prototype_foam_flow_detail) {
        vec2 momentum = vec2(textureLod(momentum_x_state, uv, 0.0).r,
            textureLod(momentum_z_state, uv, 0.0).r);
        vec2 velocity = clamp(momentum / max(depth, 0.02),
            vec2(-2.0), vec2(2.0));
        vec2 flow_position = uv_m - velocity * t * 0.12;
        float large = prototype_noise(flow_position * 1.8 + vec2(2.7, -9.4));
        float medium = prototype_noise(flow_position * 6.4 +
            vec2(14.1, 5.6) + vec2(large * 1.3));
        float fine = prototype_noise(flow_position * 15.2 + vec2(-3.8, 21.7));
        float fragmented = smoothstep(0.34, 0.66,
            large * 0.48 + medium * 0.34 + fine * 0.18);
        float core = smoothstep(0.42, 0.82, coverage);
        whitewater = smoothstep(0.10, 0.52, coverage) *
            (0.16 + 0.84 * max(core, fragmented)) *
            smoothstep(wet_epsilon_m, 0.012, depth);
    }
    if (!phase2_foam) {
        whitewater = 0.0;
    }
    if (prototype_front_foam_ribbon && prototype_use_local_front) {
        vec2 front = textureLod(local_front_state, uv, 0.0).rg;
        float distance_cells = uv.x * 256.0 - 0.5 - front.x;
        float ribbon = smoothstep(-5.0, -2.0, distance_cells) *
            (1.0 - smoothstep(0.0, 2.0, distance_cells));
        float active = smoothstep(0.0012, 0.0045, front.y);
        whitewater *= mix(0.18, 1.0, active * ribbon);
    }
    if (prototype_crest_white_face && prototype_crest_height_m > 0.0) {
        float raised_face = smoothstep(0.025, 0.17,
            crest_lift) * smoothstep(0.035, 0.10, depth);
        if (prototype_crest_broken_core && prototype_use_local_front) {
            vec2 front = textureLod(local_front_state, uv, 0.0).rg;
            float near_a = textureLod(local_front_state,
                clamp(uv + vec2(0.0, 1.0 / 256.0), vec2(0.0), vec2(1.0)), 0.0).g;
            float near_b = textureLod(local_front_state,
                clamp(uv - vec2(0.0, 1.0 / 256.0), vec2(0.0), vec2(1.0)), 0.0).g;
            float coherent = smoothstep(0.0020, 0.0045,
                min(front.y, max(near_a, near_b)));
            float distance_cells = uv.x * 256.0 - 0.5 - front.x;
            float warp = (prototype_noise(vec2(uv_m.y * 1.7 + 3.1,
                t * 0.08 + 8.7)) - 0.5) * 1.8;
            float shoulder = smoothstep(-8.2 + warp, -5.8 + warp,
                distance_cells) * (1.0 - smoothstep(0.5 + warp,
                2.7 + warp, distance_cells));
            float core = smoothstep(-5.8 + warp, -3.8 + warp,
                distance_cells) * (1.0 - smoothstep(-0.6 + warp,
                1.1 + warp, distance_cells));
            float coarse = prototype_noise(uv_m * vec2(2.4, 1.9) +
                vec2(3.7, t * 0.13));
            float fine = prototype_noise(uv_m * vec2(8.1, 6.4) +
                vec2(-6.3, t * 0.29));
            float fragments = smoothstep(0.25, 0.70,
                0.62 * coarse + 0.38 * fine);
            raised_face = coherent * smoothstep(0.012, 0.055, crest_lift) *
                smoothstep(0.035, 0.10, depth) *
                (0.28 * shoulder + 0.72 * core *
                    (0.45 + 0.55 * fragments));
        }
        if (prototype_crest_fragment_foam) {
            raised_face = smoothstep(0.08, 0.36, coverage) *
                smoothstep(0.035, 0.10, depth);
        }
        float irregular_edge = 0.72 + 0.28 * prototype_noise(
            uv_m * 3.7 + vec2(5.1, -13.4));
        if (prototype_foam_flow_detail) {
            vec2 momentum = vec2(textureLod(momentum_x_state, uv, 0.0).r,
                textureLod(momentum_z_state, uv, 0.0).r);
            vec2 velocity = clamp(momentum / max(depth, 0.02),
                vec2(-2.0), vec2(2.0));
            vec2 p = uv_m - velocity * t * 0.12;
            float large = prototype_noise(p * 2.7 + vec2(5.1, -13.4));
            float fine = prototype_noise(p * 10.3 + vec2(-7.6, 8.2));
            irregular_edge = mix(0.20, 1.0,
                smoothstep(0.30, 0.66, 0.62 * large + 0.38 * fine));
        }
        float face_foam = prototype_crest_span_smoothing ?
            smoothstep(0.04, 0.30, coverage) : 1.0;
        whitewater = max(whitewater,
            raised_face * irregular_edge * face_foam);
    }
    if (prototype_offshore_core && prototype_use_local_front) {
        vec2 front = textureLod(local_front_state, uv, 0.0).rg;
        float distance_cells = uv.x * 256.0 - 0.5 - front.x;
        float along_warp = (prototype_noise(vec2(uv_m.y * 1.5 + 4.2,
            t * 0.12)) - 0.5) * 0.9;
        float body = smoothstep(-5.5 + along_warp,
            -3.8 + along_warp, distance_cells) *
            (1.0 - smoothstep(-0.4 + along_warp,
                1.4 + along_warp, distance_cells));
        float inner = smoothstep(-3.2 + along_warp,
            -2.2 + along_warp, distance_cells) *
            (1.0 - smoothstep(-0.5 + along_warp,
                0.5 + along_warp, distance_cells));
        float broken_edge = prototype_noise(uv_m * vec2(5.2, 7.4) +
            vec2(3.8, t * 0.23));
        float activity = smoothstep(0.0032, 0.0050, front.y) *
            smoothstep(0.07, 0.16, depth);
        activity *= smoothstep(4.0, 12.0, front.x) *
            (1.0 - smoothstep(244.0, 252.0, front.x));
        if (!prototype_offshore_core_source_started) {
            activity = 0.0;
        }
        if (prototype_offshore_core_broken) {
            float broad = smoothstep(-7.0 + along_warp,
                -4.5 + along_warp, distance_cells) *
                (1.0 - smoothstep(0.3 + along_warp,
                    2.8 + along_warp, distance_cells));
            float medium = prototype_noise(uv_m * vec2(2.7, 4.1) +
                vec2(8.2, t * 0.11));
            float fine = prototype_noise(uv_m * vec2(8.8, 9.6) +
                vec2(-3.7, t * 0.19));
            float fragments = smoothstep(0.30, 0.68,
                0.56 * medium + 0.44 * fine);
            float crown_attachment = prototype_offshore_core_crown ?
                smoothstep(0.14, 0.24, crest_lift) : 1.0;
            whitewater = max(whitewater, activity * crown_attachment *
                (0.45 * broad * (0.15 + 0.85 * fragments) +
                    0.58 * inner * (0.25 + 0.75 * fragments)));
        } else {
            whitewater = max(whitewater, activity *
                (0.30 * body * smoothstep(0.28, 0.62, broken_edge) +
                    0.74 * inner));
        }
    }
    return whitewater;
}

void prototype_apply_whitewater(inout vec3 color, inout float alpha,
        vec2 uv, vec2 uv_m, float depth, float t, float crest_lift,
        vec2 screen_uv, mat4 inverse_projection_matrix, float view_z) {
    float whitewater = prototype_whitewater(uv, uv_m, depth, t, crest_lift);
    if (prototype_contact_foam_candidate) {
        ivec2 cell = clamp(ivec2(round(uv * 256.0 - vec2(0.5))),
            ivec2(0), ivec2(255));
        float current_depth = max(texelFetch(water_state, cell, 0).r, 0.0);
        float previous_depth = max(textureLod(foam_previous_state,
            (vec2(cell) + vec2(0.5)) / 256.0, 0.0).g, 0.0);
        bool near_dry = current_depth <= wet_epsilon_m;
        if (cell.x > 0) {
            near_dry = near_dry || texelFetch(water_state,
                cell + ivec2(-1, 0), 0).r <= wet_epsilon_m;
        }
        if (cell.x < 255) {
            near_dry = near_dry || texelFetch(water_state,
                cell + ivec2(1, 0), 0).r <= wet_epsilon_m;
        }
        if (cell.y > 0) {
            near_dry = near_dry || texelFetch(water_state,
                cell + ivec2(0, -1), 0).r <= wet_epsilon_m;
        }
        if (cell.y < 255) {
            near_dry = near_dry || texelFetch(water_state,
                cell + ivec2(0, 1), 0).r <= wet_epsilon_m;
        }
        if (prototype_contact_foam_spread ||
                (prototype_contact_front_gate && prototype_contact_wide_band)) {
            for (int dz = -2; dz <= 2; dz++) {
                for (int dx = -2; dx <= 2; dx++) {
                    if (abs(dx) + abs(dz) == 2) {
                        ivec2 neighbor = cell + ivec2(dx, dz);
                        if (all(greaterThanEqual(neighbor, ivec2(0))) &&
                                all(lessThanEqual(neighbor, ivec2(255)))) {
                            near_dry = near_dry || texelFetch(water_state,
                                neighbor, 0).r <= wet_epsilon_m;
                        }
                    }
                }
            }
        }
        float rising = prototype_contact_independent_history_gate ?
            smoothstep(0.45, 0.75, textureLod(contact_history_state,
                (vec2(cell) + vec2(0.5)) / 256.0, 0.0).r) :
            (prototype_contact_history_gate ?
            smoothstep(0.01, 0.08, textureLod(foam_state,
                (vec2(cell) + vec2(0.5)) / 256.0, 0.0).r) :
            (prototype_contact_front_gate ?
            smoothstep(0.0002, 0.0018, current_depth - previous_depth) :
            smoothstep(0.0015, 0.0045, current_depth - previous_depth)));
        if (prototype_contact_foam_spread) {
            float nearby_foam = 0.0;
            float nearby_front = 0.0;
            for (int dz = -4; dz <= 4; dz += 4) {
                for (int dx = -4; dx <= 4; dx += 4) {
                    ivec2 sample_cell = clamp(cell + ivec2(dx, dz),
                        ivec2(0), ivec2(255));
                    nearby_foam = max(nearby_foam, texelFetch(foam_state,
                        sample_cell, 0).r);
                    nearby_front = max(nearby_front, texelFetch(local_front_state,
                        sample_cell, 0).g);
                }
            }
            rising = smoothstep(0.01, 0.08, nearby_foam) *
                smoothstep(0.0008, 0.0020, nearby_front);
        }
        if (prototype_contact_front_gate) {
            float front_peak = textureLod(local_front_state,
                (vec2(cell) + vec2(0.5)) / 256.0, 0.0).g;
            rising *= prototype_contact_relaxed_front_gate ?
                smoothstep(0.0006, 0.0020, front_peak) :
                smoothstep(0.0012, 0.0035, front_peak);
        }
        float shallow = 1.0 - smoothstep(0.03, 0.09, depth);
        if (prototype_contact_scene_gap_gate) {
            float scene_distance = prototype_view_distance(screen_uv,
                inverse_projection_matrix);
            float gap_m = scene_distance + view_z;
            rising *= step(0.01, scene_distance) *
                smoothstep(0.0, 0.015, gap_m) *
                (1.0 - smoothstep(0.05, 0.15, gap_m));
        }
        float breakup = 0.55 + 0.45 * prototype_noise(
            uv_m * 8.0 + vec2(3.1, t * 0.3));
        whitewater = max(whitewater, float(near_dry) * rising *
            shallow * breakup * 0.8);
    }
    whitewater *= test1_whitewater_gain;
    color = mix(color, foam_tint,
        whitewater * (prototype_crest_white_face ? 0.94 : 0.78));
    alpha = mix(alpha, prototype_crest_white_face ? 0.98 : 0.93, whitewater);
}

void vertex() {
    prototype_eta_normal_local_v = vec3(0.0, 1.0, 0.0);
    vec3 surface = display_surface(UV);
    float crest_lift = prototype_crest(UV, surface.y);
    prototype_crest_lift_v = crest_lift;
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
        prototype_eta_normal_local_v = NORMAL;
    }
}

vec3 natural_scatter_color(float depth) {
    return mix(phase2_shallow_tint, phase2_deep_tint, smoothstep(0.02, 0.30, depth)) *
        mix(1.0, prototype_screen_deep_scatter_scale, smoothstep(0.08, 0.20, depth));
}

void fragment() {
    natural_optical_weights = vec2(0.0);
    natural_water_depth = 0.0;
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

    if (prototype_depth_layers_debug) {
        ALBEDO = vec3(
            step(abs(depth - 0.02), 0.01),
            step(abs(depth - 0.08), 0.01),
            step(abs(depth - 0.25), 0.01));
        ALPHA = 1.0;
    } else if (prototype_depth_gray_debug) {
        ALBEDO = vec3(clamp(depth / 0.5, 0.0, 1.0));
        ALPHA = 1.0;
    } else if (prototype_depth_bands) {
        ALBEDO = depth >= 0.20 ? vec3(0.0, 0.0, 1.0) :
            (depth >= 0.02 && depth < 0.08 ? vec3(1.0, 0.0, 0.0) :
            vec3(0.0, 1.0, 0.0));
        ALPHA = 1.0;
    } else if (false) {
        ALBEDO = vec3(1.0);
        ALPHA = 1.0;
    } else if (prototype_shore_source_debug) {
        ivec2 nearest = clamp(ivec2(round(UV * 256.0 - vec2(0.5))),
            ivec2(0), ivec2(255));
        float source_depth = texelFetch(water_state, nearest, 0).r;
        ALBEDO = source_depth > wet_epsilon_m ?
            vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        ALPHA = 1.0;
    } else if (prototype_contact_foam_source_debug) {
        ivec2 cell = clamp(ivec2(round(UV * 256.0 - vec2(0.5))),
            ivec2(0), ivec2(255));
        float center_depth = max(texelFetch(water_state, cell, 0).r, 0.0);
        float earlier_depth = max(textureLod(foam_previous_state,
            (vec2(cell) + vec2(0.5)) / 256.0, 0.0).g, 0.0);
        bool near_dry = center_depth <= wet_epsilon_m;
        if (cell.x > 0) {
            near_dry = near_dry || texelFetch(water_state,
                cell + ivec2(-1, 0), 0).r <= wet_epsilon_m;
        }
        if (cell.x < 255) {
            near_dry = near_dry || texelFetch(water_state,
                cell + ivec2(1, 0), 0).r <= wet_epsilon_m;
        }
        if (cell.y > 0) {
            near_dry = near_dry || texelFetch(water_state,
                cell + ivec2(0, -1), 0).r <= wet_epsilon_m;
        }
        if (cell.y < 255) {
            near_dry = near_dry || texelFetch(water_state,
                cell + ivec2(0, 1), 0).r <= wet_epsilon_m;
        }
        bool advancing = center_depth - earlier_depth > 0.0015;
        ALBEDO = near_dry ? (advancing ? vec3(0.0, 1.0, 0.0) :
            vec3(1.0, 0.72, 0.0)) : (advancing ? vec3(0.0, 0.4, 1.0) :
            vec3(0.15));
        ALPHA = 1.0;
    } else if (prototype_contact_depth_debug) {
        float scene_distance = prototype_view_distance(SCREEN_UV,
            INV_PROJECTION_MATRIX);
        float gap_m = scene_distance + VERTEX.z;
        ALBEDO = depth > 0.02 ? vec3(0.15) :
            (scene_distance <= 0.0 || scene_distance > 100.0 ?
            vec3(1.0, 0.0, 1.0) :
            (gap_m < -0.02 ? vec3(1.0, 0.0, 0.0) :
            (gap_m < 0.02 ? vec3(1.0, 1.0, 0.0) :
            (gap_m < 0.10 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0)))));
        ALPHA = 1.0;
    } else if (prototype_contact_height_debug) {
        float water_height = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
        float height_gap_m = water_height - coupled_bed_triangle_at(UV);
        ALBEDO = depth > 0.02 ? vec3(0.15) :
            (height_gap_m < -0.02 ? vec3(1.0, 0.0, 0.0) :
            (height_gap_m < 0.02 ? vec3(1.0, 1.0, 0.0) :
            (height_gap_m < 0.10 ? vec3(0.0, 1.0, 0.0) :
            vec3(0.0, 0.0, 1.0))));
        ALPHA = 1.0;
    } else if (prototype_vertex_fragment_delta_debug) {
        float water_height = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
        float fragment_height = surface.x + depth + water_surface_bias_m +
            prototype_crest_lift_v;
        float mismatch_m = water_height - fragment_height;
        ALBEDO = depth > 0.02 ? vec3(0.15) :
            (mismatch_m < -0.02 ? vec3(1.0, 0.0, 0.0) :
            (mismatch_m < 0.02 ? vec3(1.0, 1.0, 0.0) :
            (mismatch_m < 0.10 ? vec3(0.0, 1.0, 0.0) :
            vec3(0.0, 0.0, 1.0))));
        ALPHA = 1.0;
    } else if (prototype_visible_bed_height_debug) {
        float water_height = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
        float height_gap_m = water_height - coupled_bed_render_mesh_at(UV);
        ALBEDO = depth > 0.02 ? vec3(0.15) :
            (height_gap_m < -0.02 ? vec3(1.0, 0.0, 0.0) :
            (height_gap_m < 0.02 ? vec3(1.0, 1.0, 0.0) :
            (height_gap_m < 0.10 ? vec3(0.0, 1.0, 0.0) :
            vec3(0.0, 0.0, 1.0))));
        ALPHA = 1.0;
    } else if (prototype_contact_residual_debug) {
        float water_height = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
        float expected_height = coupled_bed_render_mesh_at(UV) + depth +
            water_surface_bias_m + prototype_crest_lift_v;
        float residual_m = water_height - expected_height;
        ALBEDO = depth > 0.02 ? vec3(0.15) :
            (residual_m < -0.02 ? vec3(1.0, 0.0, 0.0) :
            (residual_m < 0.02 ? vec3(1.0, 1.0, 0.0) :
            (residual_m < 0.10 ? vec3(0.0, 1.0, 0.0) :
            vec3(0.0, 0.0, 1.0))));
        ALPHA = 1.0;
    } else if (prototype_screen_optics) {
        // Isolated screen-space transmission/refraction route. The scene copy
        // contains the opaque sand and depth; transparent objects are excluded.
        float t = visual_time_s >= 0.0 ? visual_time_s : TIME;
        vec2 uv_m = UV * 32.0;
        float attenuation = smoothstep(0.008, 0.065, depth);
        vec2 detail = vec2(0.0);
        if (use_detail_normals && natural_normal_mode == 1) {
            detail = vec2(sin(uv_m.x * 3.1 + uv_m.y * 1.7 - t * 1.2),
                cos(uv_m.y * 2.8 - uv_m.x * 1.4 - t * 0.9)) * 0.075 * attenuation;
        } else if (use_detail_normals && natural_normal_mode == 2) {
            // RG signed slopes in local XZ; rotated UV/slopes share a basis.
            vec2 q0 = vec2(dot(uv_m, natural_direction0),
                dot(uv_m, vec2(-natural_direction0.y, natural_direction0.x)));
            vec2 q1 = vec2(dot(uv_m, natural_direction1),
                dot(uv_m, vec2(-natural_direction1.y, natural_direction1.x)));
            vec2 a = texture(natural_normal_texture,
                (q0 - vec2(t * natural_layer0.y, 0.0)) * natural_layer0.x).rg * 2.0 - 1.0;
            vec2 b = texture(natural_normal_texture,
                (q1 - vec2(t * natural_layer1.y, 0.0)) * natural_layer1.x).rg * 2.0 - 1.0;
            vec2 a_local = natural_direction0 * a.x + vec2(-natural_direction0.y, natural_direction0.x) * a.y;
            vec2 b_local = natural_direction1 * b.x + vec2(-natural_direction1.y, natural_direction1.x) * b.y;
            detail = (a_local * natural_layer0.z + b_local * natural_layer1.z) * attenuation;
        }
        vec3 detail_view = mat3(VIEW_MATRIX) *
            (MODEL_NORMAL_MATRIX * vec3(detail.x, 0.0, detail.y));
        // This double-sided mesh can reach the fragment shader as a back face.
        // Orient the macro normal before adding world-aligned detail; flipping
        // the sum would reverse the detail on that side.
        vec3 face_normal = FRONT_FACING ? NORMAL : -NORMAL;
        vec3 n = normalize(face_normal + detail_view);
        if (prototype_screen_face_normal && dot(normalize(VIEW), n) < 0.0) {
            n = -n;
        }
        NORMAL = n;
        natural_water_depth = depth;
        float surface_distance = -VERTEX.z;
        float original_distance = prototype_view_distance(SCREEN_UV,
            INV_PROJECTION_MATRIX);
        vec2 offset = n.xy * prototype_refraction_scale *
            smoothstep(0.005, 0.20, depth) *
            smoothstep(0.005, 0.08, original_distance - surface_distance);
        vec2 raw_candidate_uv = SCREEN_UV + offset;
        bool outside_screen = any(lessThan(raw_candidate_uv, vec2(0.001))) ||
            any(greaterThan(raw_candidate_uv, vec2(0.999)));
        vec2 candidate_uv = clamp(raw_candidate_uv,
            vec2(0.001), vec2(0.999));
        float candidate_distance = prototype_view_distance(candidate_uv,
            INV_PROJECTION_MATRIX);
        bool blocked_by_depth = prototype_depth_guard &&
            candidate_distance <= surface_distance + 0.005;
        vec2 sampled_uv = outside_screen && !prototype_legacy_edge_clamp ?
            SCREEN_UV : candidate_uv;
        if (blocked_by_depth) {
            sampled_uv = SCREEN_UV;
        }
        vec3 bed_color = textureLod(prototype_scene_color, sampled_uv, 0.0).rgb;
        float path_length = depth / max(abs(dot(normalize(VIEW), n)), 0.25);
        float effective_extinction = mix(prototype_shallow_extinction_m,
            prototype_deep_extinction_m, smoothstep(0.04, 0.13, depth));
        float transmission = exp(-path_length / effective_extinction);
        vec3 scatter = mix(phase2_shallow_tint, phase2_deep_tint,
            smoothstep(0.02, 0.30, depth));
        scatter *= mix(1.0, prototype_screen_deep_scatter_scale,
            smoothstep(0.08, 0.20, depth));
        vec3 transmitted = bed_color * transmission + scatter * (1.0 - transmission);
        if (prototype_optical_shallow_preserve) {
            float preserve = 1.0 - smoothstep(0.03, 0.18, depth);
            transmitted = mix(transmitted, bed_color, preserve);
        }
        if (prototype_caustic_recovery_gain > 0.0) {
            float sampled_scene_depth = textureLod(prototype_scene_depth,
                sampled_uv, 0.0).r;
            vec4 bed_view_h = INV_PROJECTION_MATRIX *
                vec4(sampled_uv * 2.0 - 1.0, sampled_scene_depth, 1.0);
            vec3 bed_view = bed_view_h.xyz / bed_view_h.w;
            vec3 bed_world = (INV_VIEW_MATRIX * vec4(bed_view, 1.0)).xyz;
            vec2 bed_uv = bed_world.xz / 32.0 + vec2(0.5);
            float line = texture(prototype_caustic_pattern,
                bed_uv * prototype_caustic_recovery_uv_scale +
                t * vec2(0.0013, -0.0007)).r;
            float recovery = prototype_caustic_recovery_gain *
                smoothstep(0.14, 0.30, depth) * exp(-depth / 0.35) *
                abs(dot(normalize(VIEW), n));
            transmitted += vec3(0.31, 0.38, 0.31) * line * recovery;
        }
        float cosine = dot(normalize(VIEW), n);
        if (prototype_screen_abs_fresnel) {
            // The prototype is double-sided; use the visible side's normal.
            cosine = abs(cosine);
        }
        float fresnel = pow(1.0 - clamp(cosine, 0.0, 1.0), 5.0);
        // The sky color is the fallback for rays without a visible scene hit.
        vec4 reflected_scene = vec4(0.55, 0.75, 0.86, 0.0);
        if (prototype_screen_scene_reflection) {
            reflected_scene = prototype_reflected_scene(VERTEX, n,
                normalize(VIEW), PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
        } else if (prototype_planar_reflection_enabled) {
            vec2 reflected_uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y);
            if (prototype_planar_reflection_projected) {
                vec4 world_position = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
                vec4 reflected_clip = prototype_planar_view_projection *
                    world_position;
                reflected_uv = reflected_clip.xy / reflected_clip.w * 0.5 + 0.5;
            }
            vec2 reflection_uv = clamp(reflected_uv, vec2(0.0), vec2(1.0));
            vec3 reflected_color = textureLod(prototype_planar_reflection,
                reflection_uv, 0.0).rgb;
            if (prototype_planar_reflection_softness_px > 0.0) {
                vec2 radius_uv = prototype_planar_reflection_softness_px /
                    vec2(textureSize(prototype_planar_reflection, 0));
                reflected_color = reflected_color * 0.36;
                reflected_color += textureLod(prototype_planar_reflection,
                    clamp(reflection_uv + radius_uv, vec2(0.0), vec2(1.0)), 0.0).rgb * 0.16;
                reflected_color += textureLod(prototype_planar_reflection,
                    clamp(reflection_uv + vec2(-radius_uv.x, radius_uv.y),
                    vec2(0.0), vec2(1.0)), 0.0).rgb * 0.16;
                reflected_color += textureLod(prototype_planar_reflection,
                    clamp(reflection_uv + vec2(radius_uv.x, -radius_uv.y),
                    vec2(0.0), vec2(1.0)), 0.0).rgb * 0.16;
                reflected_color += textureLod(prototype_planar_reflection,
                    clamp(reflection_uv - radius_uv, vec2(0.0), vec2(1.0)), 0.0).rgb * 0.16;
            }
            reflected_scene = vec4(reflected_color, 1.0);
        } else if (prototype_screen_sky_gradient) {
            vec3 ray_world = normalize(mat3(INV_VIEW_MATRIX) *
                reflect(-normalize(VIEW), n));
            float zenith = smoothstep(0.02, 0.65, max(ray_world.y, 0.0));
            reflected_scene = vec4(mix(vec3(0.73, 0.83, 0.84),
                vec3(0.36, 0.65, 0.84), zenith), 0.0);
        }
        if (prototype_screen_bed_only) {
            ALBEDO = bed_color;
            ALPHA = 1.0;
        } else if (prototype_screen_fresnel_debug) {
            ALBEDO = vec3(fresnel);
            ALPHA = 1.0;
        } else if (prototype_screen_reflection_debug) {
            ALBEDO = vec3(reflected_scene.a);
            ALPHA = 1.0;
        } else if (prototype_planar_reflection_debug) {
            ALBEDO = reflected_scene.rgb;
            ALPHA = 1.0;
        } else {
            float reflect_weight = (0.025 + 0.42 * fresnel) * prototype_screen_sky_reflection_scale;
            ALBEDO = mix(transmitted, reflected_scene.rgb, reflect_weight);
            float preserved_bed = prototype_optical_shallow_preserve ?
                1.0 - smoothstep(0.03, 0.18, depth) : 0.0;
            natural_optical_weights.x = (1.0 - transmission) *
                (1.0 - preserved_bed) * (1.0 - reflect_weight);
            if (prototype_front_face_rim_tone && prototype_use_local_front) {
                vec2 local_front = textureLod(local_front_state, UV, 0.0).rg;
                float distance_cells = UV.x * 256.0 - 0.5 - local_front.x;
                float activity = smoothstep(0.0032, 0.0050, local_front.y);
                if (prototype_front_face_source_gate &&
                        !prototype_front_face_source_started) {
                    activity = 0.0;
                }
                if (prototype_front_face_foam_gate) {
                    activity *= smoothstep(0.008, 0.060,
                        textureLod(foam_state, UV, 0.0).r);
                }
                float raised = smoothstep(0.035, 0.13,
                    prototype_crest_lift_v) *
                    smoothstep(0.045, 0.11, depth);
                // The advancing face is the positive-X downhill slope of the
                // actual raised main surface, not a camera-facing mask.
                float face = activity * raised *
                    smoothstep(0.10, 0.46,
                        max(prototype_eta_normal_local_v.x, 0.0));
                ALBEDO = mix(ALBEDO, vec3(0.018, 0.20, 0.27),
                    0.67 * face);
                float rim = smoothstep(-3.8, -2.5, distance_cells) *
                    (1.0 - smoothstep(-1.3, 0.1, distance_cells));
                float breakup = 0.62 + 0.38 * prototype_noise(
                    uv_m * vec2(4.6, 2.8) + vec2(7.2, t * 0.13));
                ALBEDO = mix(ALBEDO, foam_tint,
                    0.72 * activity * raised * rim * breakup);
            }
            if (prototype_screen_world_glint && use_specular) {
                vec3 light_view = normalize(mat3(VIEW_MATRIX) *
                    prototype_light_direction_world);
                vec3 half_view = normalize(normalize(VIEW) + light_view);
                vec3 normal_world = normalize(mat3(INV_VIEW_MATRIX) * n);
                float slope = 1.0 - abs(normal_world.y);
                float slope_gate = smoothstep(0.015, 0.14, slope);
                float glint = pow(max(dot(n, half_view), 0.0), 42.0) *
                    slope_gate * smoothstep(0.02, 0.09, depth) * 0.32;
                ALBEDO += vec3(1.0, 0.96, 0.86) * glint;
            }
            ALPHA = smoothstep(wet_epsilon_m, 0.015, depth);
            float white_fraction = prototype_whitewater(UV, uv_m, depth, t,
                prototype_crest_lift_v) * test1_whitewater_gain *
                (prototype_crest_white_face ? 0.94 : 0.78);
            natural_optical_weights.x *= 1.0 - white_fraction;
            natural_optical_weights.y = white_fraction;
            prototype_apply_whitewater(ALBEDO, ALPHA, UV, uv_m, depth, t,
                prototype_crest_lift_v, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z);
            if (display_reconstruction) {
                ALPHA *= smoothstep(0.0, 0.8, surface.z);
            }
        }
        if (natural_normal_debug == 1) {
            ALBEDO = normalize(mat3(INV_VIEW_MATRIX) * n) * 0.5 + 0.5;
            ALPHA = 1.0;
        } else if (natural_normal_debug == 2) {
            ALBEDO = vec3(detail.x * 3.0 + 0.5, 0.5, detail.y * 3.0 + 0.5);
            ALPHA = 1.0;
        }
        if (prototype_refraction_fallback_debug) {
            ALBEDO = outside_screen ? vec3(1.0, 0.0, 0.0) :
                (blocked_by_depth ? vec3(0.0, 0.0, 1.0) :
                vec3(0.0, 1.0, 0.0));
            ALPHA = 1.0;
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
            vec3 face_normal = FRONT_FACING ? NORMAL : -NORMAL;
            n = normalize(face_normal + detail_view);
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
        vec3 light_view = prototype_eta_normals ?
            normalize(mat3(VIEW_MATRIX) * prototype_light_direction_world) :
            normalize(vec3(-0.10, 0.10, 0.99));
        float glint = use_specular ? pow(max(0.0, dot(n,
            light_view)), 28.0) * 0.12 * attenuation : 0.0;
        ALBEDO = mix(scatter, vec3(0.53, 0.78, 0.79), reflection) + vec3(glint);
        ALPHA = clamp(depth_fraction * (1.0 - reflection) + reflection * 0.75,
            0.0, 0.95) * smoothstep(wet_epsilon_m, 0.018, depth);
        prototype_apply_whitewater(ALBEDO, ALPHA, UV, uv_m, depth, t,
            prototype_crest_lift_v, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z);
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
    if (prototype_contact_alpha_debug) {
        float drawn_alpha = ALPHA;
        ALBEDO = drawn_alpha < 0.05 ? vec3(1.0, 0.0, 0.0) :
            (drawn_alpha < 0.20 ? vec3(1.0, 1.0, 0.0) :
            vec3(0.0, 1.0, 0.0));
        ALPHA = 1.0;
    } else if (prototype_eta_light_space_debug) {
        vec3 local_normal = normalize(prototype_eta_normal_local_v);
        vec3 view_normal = normalize(FRONT_FACING ? NORMAL : -NORMAL);
        vec3 world_light = normalize(prototype_light_direction_world);
        vec3 view_light = normalize(mat3(VIEW_MATRIX) * world_light);
        float discrepancy = abs(dot(local_normal, world_light) -
            dot(view_normal, view_light));
        ALBEDO = vec3(clamp(discrepancy * 32.0, 0.0, 1.0));
        ALPHA = 1.0;
    } else if (prototype_eta_normal_space_debug) {
        vec3 local_normal = normalize(prototype_eta_normal_local_v);
        vec3 view_as_world = normalize(mat3(INV_VIEW_MATRIX) *
            (FRONT_FACING ? NORMAL : -NORMAL));
        ALBEDO = clamp(abs(view_as_world - local_normal) * 8.0,
            vec3(0.0), vec3(1.0));
        ALPHA = 1.0;
    } else if (prototype_eta_normal_debug) {
        vec3 local_normal = normalize(prototype_eta_normal_local_v);
        ALBEDO = clamp(vec3(0.5) +
            vec3(local_normal.x * 4.0, 0.0, local_normal.z * 4.0),
            vec3(0.0), vec3(1.0));
        ALPHA = 1.0;
    }
    vec3 direct_layer = natural_scatter_color(natural_water_depth) * natural_optical_weights.x * natural_scatter_direct_fraction +
        foam_tint * natural_optical_weights.y * natural_foam_direct_fraction;
    EMISSION = ALBEDO - direct_layer;
    ALBEDO = vec3(1.0);
    SPECULAR = 0.0;
    if (natural_normal_debug > 0) {
        EMISSION += direct_layer;
        natural_optical_weights = vec2(0.0);
        natural_water_depth = 0.0;
    }
    if (natural_lighting_debug > 0) {
        EMISSION = vec3(0.0);
        ALPHA = 1.0;
    }

}



void light() {
    if (LIGHT_IS_DIRECTIONAL) {
        vec3 irradiance = LIGHT_COLOR / PI * ATTENUATION;
        vec3 scatter_layer = natural_scatter_color(natural_water_depth) * natural_optical_weights.x;
        vec3 foam_layer = foam_tint * natural_optical_weights.y;
        vec3 direct = (scatter_layer * natural_scatter_direct_fraction +
            foam_layer * natural_foam_direct_fraction) *
            max(dot(NORMAL, LIGHT), 0.0) * irradiance;
        vec3 half_direction = normalize(VIEW + LIGHT);
        float glint = natural_glint_enabled && use_specular ?
            pow(max(dot(NORMAL, half_direction), 0.0), natural_glint_exponent) *
            natural_glint_gain * smoothstep(0.008, 0.05, natural_water_depth) : 0.0;
        vec3 specular_term = vec3(1.0, 0.96, 0.86) * glint * irradiance;
        if (natural_lighting_debug == 1) {
            SPECULAR_LIGHT += specular_term;
        } else if (natural_lighting_debug == 2) {
            DIFFUSE_LIGHT += vec3(ATTENUATION);
        } else if (natural_lighting_debug == 3) {
            DIFFUSE_LIGHT += scatter_layer * max(dot(NORMAL, LIGHT), 0.0) * irradiance;
        } else if (natural_lighting_debug == 4) {
            DIFFUSE_LIGHT += foam_layer * max(dot(NORMAL, LIGHT), 0.0) * irradiance;
        } else {
            DIFFUSE_LIGHT += direct;
            SPECULAR_LIGHT += specular_term;
        }
    }
}
