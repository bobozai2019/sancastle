shader_type spatial;
render_mode cull_disabled, vertex_lighting, specular_disabled;

// S03 sand-only presentation. Authority remains the R32F rock+sand fields;
// interpolation and lighting never feed a simulation pass.
uniform bool natural_caustic_override = false;
uniform bool natural_caustic_enabled = true;
uniform float natural_caustic_strength = 0.8;
uniform float natural_caustic_softness = 1.0;
uniform float natural_caustic_uv_scale = 2.0;
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
uniform bool use_async_clock = false;
uniform sampler2D async_clock : filter_nearest, repeat_disable;
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
    if (!true) {
        return textureLod(rock_state, uv, 0.0).r +
            textureLod(sand_state, uv, 0.0).r;
    }
    vec2 cell = uv * 256.0 - vec2(0.5);
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
    vec2 half_cell = vec2(0.5 / 256.0);
    float slope_x = (bed_at(UV + vec2(half_cell.x, 0.0)) -
        bed_at(UV - vec2(half_cell.x, 0.0))) / (32.0 / 256.0);
    float slope_z = (bed_at(UV + vec2(0.0, half_cell.y)) -
        bed_at(UV - vec2(0.0, half_cell.y))) / (32.0 / 256.0);
    NORMAL = normalize(vec3(-slope_x, 1.0, -slope_z));
    sand_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

uniform bool rdc_caustics_enabled = false;
uniform sampler3D rdc_caustic_volume : filter_linear_mipmap, repeat_enable;
uniform sampler2D rdc_phase_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D rdc_momentum_x : filter_nearest, repeat_disable;
uniform sampler2D rdc_momentum_z : filter_nearest, repeat_disable;
uniform float rdc_caustic_scale = 0.25;
uniform float rdc_caustic_depth_decay = 1.2;
uniform float rdc_caustic_time_scale = 1.0;

void fragment() {
    // The terrain grid is visible from its back face in the inherited scene.
    // Supply the heightfield's upward world normal explicitly for lighting.
    NORMAL = normalize((VIEW_MATRIX * vec4(sand_world_normal, 0.0)).xyz);
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
        ALBEDO = vec3(0.28, 0.27, 0.26);
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
        // Direct light and cast shadows come from the scene sun. The grain
        // modulation above remains a material detail, not a baked light term.
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
    if (debug_mode == 0 && phase2_caustics && (!natural_caustic_override || natural_caustic_enabled)) {
        float depth = texture(water_state, UV).r;
        if (depth > 0.001) {
            float t = use_async_clock ? textureLod(async_clock, vec2(0.5), 0.0).r : (visual_time_s >= 0.0 ? visual_time_s : TIME);
            float line = 0.0;
            if (rdc_caustics_enabled) {
                // Local phase uses the existing captured normal B channel; original Sand.G is not mapped here.
                vec2 p = sand_world_position.xz;
                float clock = t*rdc_caustic_time_scale;
                float g = texture(rdc_phase_texture,p*0.3).b;
                float phase = g+0.5*clock;
                float a = fract(phase), b = fract(phase+0.5);
                vec2 flow = clamp(vec2(texture(rdc_momentum_x,UV).r,
                    texture(rdc_momentum_z,UV).r)/max(depth,0.02),vec2(-2.0),vec2(2.0));
                vec2 base_uv = p*rdc_caustic_scale+sand_world_normal.xz*0.1;
                float ca = texture(rdc_caustic_volume,vec3(base_uv-flow*(2.0*b-1.0)*0.1-vec2(0.5),(g+clock-0.5)*0.2)).r;
                float cb = texture(rdc_caustic_volume,vec3(base_uv-flow*(2.0*a-1.0)*0.1+vec2(0.5),(g+clock+0.5)*0.2)).r;
                line = mix(cb,ca,2.0*abs(a-0.5));
            } else if (prototype_texture_caustics) {
                vec2 caustic_uv = UV * (natural_caustic_override ? natural_caustic_uv_scale : prototype_caustic_uv_scale) +
                    t * vec2(0.0013, -0.0007);
                line = texture(caustic_pattern, caustic_uv).r;
                if ((natural_caustic_override ? natural_caustic_softness : prototype_caustic_softness) > 0.0) {
                    float soft_line = textureLod(caustic_pattern, caustic_uv, 2.0).r;
                    float broad_light = textureLod(caustic_pattern, caustic_uv, 5.0).r;
                    line = mix(line, 0.76 * sqrt(max(soft_line, 0.0)) +
                        0.24 * broad_light, clamp((natural_caustic_override ? natural_caustic_softness : prototype_caustic_softness), 0.0, 1.0));
                }
            } else {
                vec2 p = UV * 32.0 * 6.0;
                p += vec2(sin(p.y * 0.39 + t * 0.41) * 1.15 +
                    sin(p.x * 0.23 - t * 0.31) * 0.45,
                    cos(p.x * 0.42 - t * 0.36) * 0.95);
                float a = sin(p.x + 0.55 * sin(p.y * 0.87 + t * 0.55));
                float b = sin(p.y * 0.73 + 0.50 * sin(p.x * 0.63 - t * 0.48));
                line = 1.0 - smoothstep(0.045, 0.22, abs(a + b));
            }
            float visibility = exp(-depth / prototype_caustic_depth_decay_m) *
                smoothstep(0.005, 0.035, depth);
            if (rdc_caustics_enabled) {
                visibility = exp(-depth*rdc_caustic_depth_decay)*smoothstep(0.005,0.035,depth)*
                    smoothstep(0.2,0.3,max(sand_world_normal.y,0.0));
                if (natural_caustic_strength>0.0) ALBEDO = clamp(ALBEDO+vec3(line*visibility*natural_caustic_strength),vec3(0.0),vec3(1.0));
            } else ALBEDO += (prototype_texture_caustics ? vec3(0.31, 0.38, 0.31) :
                vec3(0.17, 0.22, 0.18)) * line * visibility *
                (natural_caustic_override ? natural_caustic_strength : prototype_caustic_strength);
        }
    }
}

