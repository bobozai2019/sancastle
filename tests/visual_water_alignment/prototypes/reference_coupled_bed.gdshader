shader_type spatial;
render_mode unshaded, cull_disabled;

// S03 sand-only presentation. Authority remains the R32F rock+sand fields;
// interpolation and lighting never feed a simulation pass.
uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D wetness_state : filter_nearest, repeat_disable;
uniform sampler2D compaction_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform bool display_reconstruction = true;
uniform bool phase2_caustics = false;
uniform float prototype_caustic_strength = 1.0;
uniform float prototype_caustic_depth_decay_m = 0.17;
uniform float prototype_caustic_uv_scale = 1.0;
uniform float prototype_caustic_softness = 0.0;
uniform bool prototype_texture_caustics = false;
uniform sampler2D caustic_pattern : filter_linear_mipmap, repeat_enable;
uniform float visual_time_s = -1.0;
uniform bool use_grain = true;
uniform bool use_grain_normal = true;
uniform bool use_wet_finish = true;
uniform float prototype_wet_trace_gain = 0.0;
uniform bool use_compaction_tint = true;
uniform int debug_mode = 0;
uniform float grid_size = 256.0;
uniform float domain_size_m = 32.0;
varying vec3 sand_world_position;
varying vec3 sand_world_normal;

float grain_hash(vec3 cell) {
    return fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

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
    if (weight.x + weight.y <= 1.0) {
        return v00 + weight.x * (v10 - v00) + weight.y * (v01 - v00);
    }
    return v11 + (1.0 - weight.x) * (v01 - v11) +
        (1.0 - weight.y) * (v10 - v11);
}

void vertex() {
    VERTEX.y = bed_at(UV);
    sand_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 half_cell = vec2(0.5 / grid_size);
    float slope_x = (bed_at(UV + vec2(half_cell.x, 0.0)) -
        bed_at(UV - vec2(half_cell.x, 0.0))) / (domain_size_m / grid_size);
    float slope_z = (bed_at(UV + vec2(0.0, half_cell.y)) -
        bed_at(UV - vec2(0.0, half_cell.y))) / (domain_size_m / grid_size);
    NORMAL = normalize(vec3(-slope_x, 1.0, -slope_z));
    sand_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float wet = clamp(texture(wetness_state, UV).r, 0.0, 1.0);
    float compact = clamp(texture(compaction_state, UV).r, 0.0, 1.0);
    float sand = max(texture(sand_state, UV).r, 0.0);
    if (debug_mode == 1) {
        float bed = clamp(bed_at(UV) / 2.3, 0.0, 1.0);
        ALBEDO = mix(vec3(0.08, 0.17, 0.47), vec3(0.96, 0.84, 0.31), bed);
        ROUGHNESS = 1.0;
    } else if (debug_mode == 4) {
        ALBEDO = mix(vec3(0.65, 0.49, 0.19), vec3(0.07, 0.36, 0.92), wet);
        ROUGHNESS = 1.0;
    } else if (debug_mode == 5) {
        ALBEDO = mix(vec3(0.15, 0.12, 0.12), vec3(0.95, 0.23, 0.08), compact);
        ROUGHNESS = 1.0;
    } else if (sand < 0.02) {
        // Most of the coupled seafloor is bare rock. Avoid seven grain hashes
        // and a per-fragment normal perturbation under every water pixel.
        vec3 light_direction = normalize(vec3(-0.42, 0.84, 0.34));
        float diffuse = max(dot(normalize(sand_world_normal), light_direction), 0.0);
        ALBEDO = vec3(0.28, 0.27, 0.26) * (0.55 + 0.45 * diffuse);
        ROUGHNESS = 0.96;
        SPECULAR = 0.16;
        METALLIC = 0.0;
    } else {
        vec3 dry = vec3(0.76, 0.59, 0.35);
        vec3 damp = vec3(0.52, 0.41, 0.28);
        vec3 color = mix(dry, damp, (use_wet_finish ? wet : 0.0) * 0.65);
        if (use_compaction_tint) {
            color = mix(color, color * vec3(0.89, 0.91, 0.96), compact * 0.25);
        }
        // 3.3 cm grains in world metres. Screen derivatives fade the pattern
        // before a grain becomes smaller than a pixel, avoiding distant crawl.
        vec3 grain_uv = sand_world_position * 30.0;
        vec3 shaded_normal = normalize(sand_world_normal);
        vec3 grain_cell = floor(grain_uv);
        float grain = grain_hash(grain_cell);
        float grain_footprint = max(length(fwidth(grain_uv)), 0.0);
        float grain_visibility = (use_grain ? 1.0 : 0.0) *
            (1.0 - smoothstep(1.0, 2.3, grain_footprint));
        color *= 1.0 + (grain - 0.5) * 0.16 * grain_visibility;
        if (use_grain_normal && use_grain) {
            vec3 key_light = normalize(vec3(-0.42, 0.84, 0.34));
            float shade_before = dot(shaded_normal, key_light);
            vec3 grain_slope = vec3(
                grain_hash(grain_cell + vec3(1.0, 0.0, 0.0)) -
                    grain_hash(grain_cell + vec3(-1.0, 0.0, 0.0)),
                grain_hash(grain_cell + vec3(0.0, 1.0, 0.0)) -
                    grain_hash(grain_cell + vec3(0.0, -1.0, 0.0)),
                grain_hash(grain_cell + vec3(0.0, 0.0, 1.0)) -
                    grain_hash(grain_cell + vec3(0.0, 0.0, -1.0)));
            shaded_normal = normalize(shaded_normal + grain_slope *
                (0.22 * grain_visibility));
            float shade_after = dot(shaded_normal, key_light);
            color *= clamp(1.0 + (shade_after - shade_before) * 0.65,
                0.82, 1.18);
        }
        float exposed_rock = 1.0 - smoothstep(0.02, 0.16, sand);
        ALBEDO = mix(color, vec3(0.28, 0.27, 0.26), exposed_rock * 0.85);
        vec3 light_direction = normalize(vec3(-0.42, 0.84, 0.34));
        float diffuse = max(dot(shaded_normal, light_direction), 0.0);
        vec3 view_direction = normalize(INV_VIEW_MATRIX[3].xyz - sand_world_position);
        float wet_highlight = pow(max(dot(reflect(-light_direction,
            shaded_normal), view_direction), 0.0), 24.0);
        ALBEDO = ALBEDO * (0.55 + 0.45 * diffuse) +
            vec3(0.17, 0.15, 0.12) * wet_highlight * wet;
        // Diagnostic only: emphasize exposed sand still carrying GPU wetness.
        // The ambient 0.15 starting wetness stays below the lower threshold.
        float exposed_trace = (1.0 - smoothstep(0.001, 0.015,
            texture(water_state, UV).r)) * smoothstep(0.26, 0.45, wet);
        ALBEDO *= mix(vec3(1.0), vec3(0.82, 0.84, 0.87),
            exposed_trace * prototype_wet_trace_gain);
        ROUGHNESS = mix(0.94, 0.68, use_wet_finish ? wet : 0.0) -
            (use_compaction_tint ? compact * 0.035 : 0.0) +
            (grain - 0.5) * 0.08 * grain_visibility;
        ROUGHNESS = clamp(ROUGHNESS, 0.48, 1.0);
        SPECULAR = use_wet_finish ? mix(0.16, 0.42, wet) : 0.16;
        METALLIC = 0.0;
    }
    // Isolated W07 parity trial: use the fixed-bed optical bright-line function
    // on the coupled bed without changing sand or water state.
    if (debug_mode == 0 && phase2_caustics) {
        float depth = texture(water_state, UV).r;
        if (depth > 0.001) {
            float t = visual_time_s >= 0.0 ? visual_time_s : TIME;
            float line = 0.0;
            if (prototype_texture_caustics) {
                vec2 caustic_uv = UV * prototype_caustic_uv_scale +
                    t * vec2(0.0013, -0.0007);
                line = texture(caustic_pattern, caustic_uv).r;
                if (prototype_caustic_softness > 0.0) {
                    float soft_line = textureLod(caustic_pattern, caustic_uv, 2.0).r;
                    float broad_light = textureLod(caustic_pattern, caustic_uv, 5.0).r;
                    line = mix(line, 0.76 * sqrt(max(soft_line, 0.0)) +
                        0.24 * broad_light, clamp(prototype_caustic_softness, 0.0, 1.0));
                }
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
            ALBEDO += (prototype_texture_caustics ? vec3(0.31, 0.38, 0.31) :
                vec3(0.17, 0.22, 0.18)) * line * visibility *
                prototype_caustic_strength;
        }
    }
}
