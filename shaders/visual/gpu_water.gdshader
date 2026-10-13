shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// T07 G01/G02: make depth, flow and foam readable from the normal view, with no
// lighting pass and no physics writes. Everything here is a pure function of the
// state textures the simulation already publishes.

uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D momentum_x_state : filter_nearest, repeat_disable;
uniform sampler2D momentum_z_state : filter_nearest, repeat_disable;
uniform sampler2D foam_state : filter_linear, repeat_disable;

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
    vec2 blend = fract(cell);
    blend = blend * blend * (vec2(3.0) - vec2(2.0) * blend);
    vec4 s00 = state_cell(low);
    vec4 s10 = state_cell(low + ivec2(1, 0));
    vec4 s01 = state_cell(low + ivec2(0, 1));
    vec4 s11 = state_cell(low + ivec2(1, 1));
    vec4 combined = mix(mix(s00, s10, blend.x), mix(s01, s11, blend.x), blend.y);
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

void vertex() {
    vec3 surface = display_surface(UV);
    VERTEX.y = surface.x + surface.y + water_surface_bias_m;
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
            float breakup = 0.5 + 0.5 * sin(uv_m.x * 7.3 +
                1.8 * sin(uv_m.y * 4.7 + t * 0.4)) *
                sin(uv_m.y * 8.1 - uv_m.x * 1.9 - t * 0.3);
            float whitewater = smoothstep(0.13, 0.62, coverage * breakup) *
                smoothstep(wet_epsilon_m, 0.012, depth);
            ALBEDO = mix(ALBEDO, foam_tint, whitewater * 0.78);
            ALPHA = mix(ALPHA, 0.93, whitewater);
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
}
