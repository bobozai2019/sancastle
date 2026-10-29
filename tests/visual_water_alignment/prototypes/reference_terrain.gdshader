shader_type spatial;
render_mode unshaded, cull_disabled;

// T07 G01/G03: readable form and material state with no lighting pass.
//
// The normal view has no DirectionalLight, so the surface used to read as a flat
// wash and dunes, the channel and player-built structures were hard to tell
// apart. The `else` branch now shades a slope-derived normal, separates dry /
// damp / wet / compacted sand, and tints the bed under water so submerged terrain
// reads as submerged instead of as bright dry sand.
//
// Debug views keep their own palettes: shading would distort the encoding.
// Nothing here writes simulation state; the presentation layer only reads it.

uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D wetness_state : filter_nearest, repeat_disable;
uniform sampler2D compaction_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D momentum_x_state : filter_nearest, repeat_disable;
uniform sampler2D momentum_z_state : filter_nearest, repeat_disable;
uniform sampler2D sediment_state : filter_nearest, repeat_disable;
uniform sampler2D obstacle_state : filter_nearest, repeat_disable;
uniform sampler2D flux_state : filter_nearest, repeat_disable;
uniform sampler2D chunk_debug_state : filter_nearest, repeat_disable;
uniform float flux_color_scale_m3_s = 0.001;
uniform int debug_mode = 0;
uniform bool apply_underwater_tint = true;
uniform float underwater_relief_boost = 0.0;
uniform bool phase2_caustics = false;
uniform float prototype_caustic_strength = 1.0;
uniform float prototype_caustic_depth_decay_m = 0.17;
uniform float prototype_caustic_uv_scale = 1.0;
uniform bool prototype_texture_caustics = false;
uniform sampler2D caustic_pattern : filter_linear_mipmap, repeat_enable;
uniform float visual_time_s = -1.0;
uniform bool display_reconstruction = false;

// Needed to turn a texture-space height difference into a real slope.
uniform float grid_size = 256.0;
uniform float domain_size_m = 32.0;
// Key direction for the unshaded form shading, chosen to front-light the default
// player camera.
uniform vec3 sun_direction = vec3(-0.42, 0.84, 0.34);

varying vec3 surface_normal;

float bed_cell(ivec2 cell) {
    ivec2 safe_cell = clamp(cell, ivec2(0), ivec2(255));
    return texelFetch(rock_state, safe_cell, 0).r +
        texelFetch(sand_state, safe_cell, 0).r;
}

float bed_at(vec2 uv) {
    if (!display_reconstruction) {
        return textureLod(rock_state, uv, 0.0).r +
            textureLod(sand_state, uv, 0.0).r;
    }
    vec2 cell = uv * grid_size - vec2(0.5);
    ivec2 low = ivec2(floor(cell));
    vec2 weight = fract(cell);
    float v00 = bed_cell(low);
    float v10 = bed_cell(low + ivec2(1, 0));
    float v01 = bed_cell(low + ivec2(0, 1));
    float v11 = bed_cell(low + ivec2(1, 1));
    // Match the visible grid diagonal and the coupled bed reconstruction.
    if (weight.x + weight.y <= 1.0) {
        return v00 + weight.x * (v10 - v00) + weight.y * (v01 - v00);
    }
    return v11 + (1.0 - weight.x) * (v01 - v11) +
        (1.0 - weight.y) * (v10 - v11);
}

void vertex() {
    float rock = textureLod(rock_state, UV, 0.0).r;
    float sand = textureLod(sand_state, UV, 0.0).r;
    VERTEX.y = display_reconstruction ? bed_at(UV) : rock + sand;
    // Central differences across one cell give a normal for the unshaded pass.
    vec2 step_uv = vec2(1.0 / grid_size, 1.0 / grid_size);
    float metres_per_step = 2.0 * domain_size_m / grid_size;
    float slope_x = (bed_at(UV + vec2(step_uv.x, 0.0)) - bed_at(UV - vec2(step_uv.x, 0.0)))
        / metres_per_step;
    float slope_z = (bed_at(UV + vec2(0.0, step_uv.y)) - bed_at(UV - vec2(0.0, step_uv.y)))
        / metres_per_step;
    surface_normal = normalize(vec3(-slope_x, 1.0, -slope_z));
}

void fragment() {
    float rock = texture(rock_state, UV).r;
    float wetness = texture(wetness_state, UV).r;
    float sand = texture(sand_state, UV).r;
    float depth = texture(water_state, UV).r;
    float compaction = texture(compaction_state, UV).r;
    if (debug_mode == 1) {
        float value = clamp((rock + sand + 0.3) / 1.0, 0.0, 1.0);
        ALBEDO = mix(vec3(0.08, 0.17, 0.47), vec3(0.96, 0.84, 0.31), value);
    } else if (debug_mode == 2) {
        float value = clamp(depth / 0.25, 0.0, 1.0);
        ALBEDO = mix(vec3(0.12, 0.12, 0.12), vec3(0.05, 0.62, 0.95), value);
    } else if (debug_mode == 3) {
        float qx = texture(momentum_x_state, UV).r;
        float qz = texture(momentum_z_state, UV).r;
        vec2 velocity = vec2(qx, qz) / max(depth, 0.001);
        float speed = clamp(length(velocity) / 0.1, 0.0, 1.0);
        ALBEDO = mix(vec3(0.12, 0.12, 0.12),
            vec3(0.5 + 0.5 * velocity.x / max(length(velocity), 0.0001),
                 0.2 + 0.6 * speed,
                 0.5 + 0.5 * velocity.y / max(length(velocity), 0.0001)), speed);
    } else if (debug_mode == 4) {
        ALBEDO = mix(vec3(0.65, 0.49, 0.19), vec3(0.07, 0.36, 0.92),
            clamp(wetness, 0.0, 1.0));
    } else if (debug_mode == 5) {
        ALBEDO = mix(vec3(0.15, 0.12, 0.12), vec3(0.95, 0.23, 0.08),
            clamp(compaction, 0.0, 1.0));
    } else if (debug_mode == 6) {
        ALBEDO = mix(vec3(0.18, 0.16, 0.15), vec3(0.93, 0.74, 0.27),
            clamp(sand / 0.8, 0.0, 1.0));
    } else if (debug_mode == 7) {
        float suspended = texture(sediment_state, UV).r;
        ALBEDO = mix(vec3(0.11, 0.12, 0.17), vec3(0.95, 0.53, 0.12),
            clamp(suspended / 0.02, 0.0, 1.0));
    } else if (debug_mode == 8) {
        float blocked = texture(obstacle_state, UV).r;
        ALBEDO = mix(vec3(0.10, 0.35, 0.21), vec3(0.96, 0.13, 0.12),
            step(0.5, blocked));
    } else if (debug_mode >= 9 && debug_mode <= 12) {
        vec4 outflow = texture(flux_state, UV);
        float rate = outflow[debug_mode - 9];
        vec3 channel_color = vec3(0.12, 0.72, 0.97);
        if (debug_mode == 10) {
            channel_color = vec3(0.95, 0.46, 0.12);
        } else if (debug_mode == 11) {
            channel_color = vec3(0.55, 0.75, 0.20);
        } else if (debug_mode == 12) {
            channel_color = vec3(0.78, 0.32, 0.90);
        }
        float intensity = clamp(log(1.0 + max(rate, 0.0) / 0.000001) /
            log(1.0 + flux_color_scale_m3_s / 0.000001), 0.0, 1.0);
        ALBEDO = mix(vec3(0.08, 0.09, 0.11), channel_color, intensity);
    } else if (debug_mode == 13) {
        float state = texture(chunk_debug_state, UV).r;
        ALBEDO = state > 0.9 ? vec3(0.95, 0.16, 0.11) :
            (state > 0.4 ? vec3(0.98, 0.76, 0.12) : vec3(0.09, 0.30, 0.23));
    } else if (debug_mode == 14) {
        float state = texture(chunk_debug_state, UV).r;
        ALBEDO = state > 0.9 ? vec3(0.84, 0.14, 0.85) :
            mix(vec3(0.09, 0.46, 0.19), vec3(0.95, 0.12, 0.10),
                clamp((state - 0.25) * 2.0, 0.0, 1.0));
    } else {
        // Dry sand is the warm reference; damp darkens it, wet darkens it more,
        // and compaction reads as firmer by cooling it slightly.
        vec3 sand_color = mix(vec3(0.78, 0.62, 0.37), vec3(0.38, 0.31, 0.23),
            clamp(wetness, 0.0, 1.0) * 0.65);
        sand_color = mix(sand_color, sand_color * vec3(0.86, 0.89, 0.95),
            clamp(compaction, 0.0, 1.0) * 0.35);
        float exposed_rock = clamp((0.30 - sand) / 0.25, 0.0, 1.0);
        vec3 color = mix(sand_color, vec3(0.28, 0.27, 0.26), exposed_rock * 0.85);

        // Submerged bed reads as underwater rather than as bright dry sand.
        if (apply_underwater_tint) {
            float submerged = 1.0 - exp(-depth / 0.09);
            color = mix(color, color * vec3(0.44, 0.63, 0.80), submerged * 0.78);
        }
        if (phase2_caustics && depth > 0.001) {
            float t = visual_time_s >= 0.0 ? visual_time_s : TIME;
            float line = 0.0;
            if (prototype_texture_caustics) {
                line = texture(caustic_pattern,
                    UV * prototype_caustic_uv_scale +
                    t * vec2(0.0013, -0.0007)).r;
            } else {
                vec2 p = UV * domain_size_m * 6.0;
                p += vec2(sin(p.y * 0.39 + t * 0.41) * 1.15 +
                    sin(p.x * 0.23 - t * 0.31) * 0.45,
                    cos(p.x * 0.42 - t * 0.36) * 0.95);
                float a = sin(p.x + 0.55 * sin(p.y * 0.87 + t * 0.55));
                float b = sin(p.y * 0.73 + 0.50 * sin(p.x * 0.63 - t * 0.48));
                line = 1.0 - smoothstep(0.045, 0.22, abs(a + b));
            }
            float visibility = exp(-depth / prototype_caustic_depth_decay_m) *
                smoothstep(0.005, 0.035, depth);
            color += (prototype_texture_caustics ? vec3(0.31, 0.38, 0.31) :
                vec3(0.17, 0.22, 0.18)) * line * visibility *
                prototype_caustic_strength;
        }

        // T07 G02 wet edge: the band the water has just left stays a shade darker
        // than the surrounding damp sand, so the receded waterline is readable.
        // It rides the wetness field, so it tracks the tide rather than sitting
        // on a fixed contour.
        float exposed = (1.0 - smoothstep(0.0, 0.02, depth)) *
            smoothstep(0.75, 1.0, wetness);
        color = mix(color, color * vec3(0.60, 0.60, 0.63), exposed * 0.55);

        // Form shading centred on flat ground, so slopes gain relief without
        // shifting the overall tone the scene was tuned to.
        vec3 sun = normalize(sun_direction);
        float shade = dot(normalize(surface_normal), sun);
        float relief_gain = 0.6 + underwater_relief_boost *
            smoothstep(0.001, 0.03, depth);
        color *= clamp(1.0 + (shade - sun.y) * relief_gain, 0.45, 1.45);
        ALBEDO = color;
    }
}
