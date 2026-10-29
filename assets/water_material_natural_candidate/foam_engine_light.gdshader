shader_type spatial;
render_mode ambient_light_disabled, cull_disabled, blend_mix, depth_draw_never;

// W07 isolated horizontal foam splats. Each quad is anchored to the same
// reconstructed eta used by the flat reference water and writes no depth.
uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D foam_state : filter_linear, repeat_disable;
uniform sampler2D rise_front_state : filter_nearest, repeat_disable;
uniform sampler2D local_front_state : filter_linear, repeat_disable;
uniform bool display_reconstruction = true;
uniform bool front_concentrated = false;
uniform bool front_local_dense = false;
uniform bool front_smooth_support = false;
uniform bool raised_local_front = false;
uniform float crest_height_m = 0.0;
uniform float surface_bias_m = 0.018;
uniform float splat_half_width_m = 0.055;
uniform float splat_jitter_m = 0.0;
uniform float target_diameter_px = 0.0;
uniform float viewport_height_px = 1080.0;
uniform float natural_foam_direct_fraction = 0.50;
uniform int natural_lighting_debug = 0;
varying vec3 natural_foam_color;
varying vec2 splat_uv;
varying vec2 domain_uv;
varying float splat_seed;
varying float front_activity;

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

float local_crest(vec2 uv, float depth) {
    if (!raised_local_front || crest_height_m <= 0.0) {
        return 0.0;
    }
    // Match reference_water_local_front.gdshader's vertex displacement.
    vec2 front = textureLod(local_front_state, uv, 0.0).rg;
    float distance_cells = uv.x * 256.0 - 0.5 - front.x;
    float shoulder = smoothstep(-7.5, -1.0, distance_cells);
    float face = 1.0 - smoothstep(0.0, 1.8, distance_cells);
    float lift = crest_height_m * smoothstep(0.0012, 0.0045, front.y) *
        shoulder * face * smoothstep(0.012, 0.065, depth);
    return min(lift, max(depth, 0.0) * 1.5);
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
    vec2 id = floor(UV * (front_local_dense ? vec2(128.0, 256.0) :
        (front_concentrated ? vec2(32.0, 256.0) : vec2(256.0))));
    splat_seed = hash21(id);
    float variation = mix(0.65, 1.3, hash21(id + vec2(17.0, 31.0)));
    vec2 jitter = (vec2(hash21(id + vec2(41.0, 9.0)),
        hash21(id + vec2(7.0, 53.0))) * 2.0 - vec2(1.0)) *
        splat_jitter_m;
    front_activity = 1.0;
    if (front_concentrated) {
        vec2 front = textureLod(rise_front_state, vec2(UV.y, 0.5), 0.0).rg;
        float front_strength = front.y;
        if (front_smooth_support) {
            float support = 0.0;
            float position_weight = 0.0;
            float position_sum = 0.0;
            for (int row_offset = -12; row_offset <= 12; row_offset += 4) {
                float row_uv = clamp(UV.y + float(row_offset) / 256.0,
                    0.5 / 256.0, 255.5 / 256.0);
                vec2 nearby = textureLod(rise_front_state,
                    vec2(row_uv, 0.5), 0.0).rg;
                float weight = row_offset == 0 ? 0.24 :
                    abs(row_offset) == 4 ? 0.20 :
                    abs(row_offset) == 8 ? 0.12 : 0.06;
                support += nearby.y * weight;
                float position_factor = nearby.y * nearby.y;
                position_weight += position_factor;
                position_sum += nearby.x * position_factor;
            }
            front_strength = support;
            if (position_weight > 1e-10) {
                front.x = position_sum / position_weight;
            }
        }
        float front_x_m = (front.x + 0.5) * 0.125 - 16.0;
        // 32 slots span 1.24 m across the active advancing front.
        VERTEX.x = front_x_m + (UV.x - 0.5) * 1.24;
        front_activity = smoothstep(0.0020, 0.0045, front_strength);
    } else if (front_local_dense) {
        // Fixed candidates cover the estuary's measured active X envelope.
        // The two-dimensional field selects the finite branch at each row.
        float candidate_cell = 64.0 + UV.x * 128.0;
        VERTEX.x = (candidate_cell + 0.5) * 0.125 - 16.0;
        vec2 sample_uv = vec2((VERTEX.x + 16.0) / 32.0, UV.y);
        vec2 local_front = textureLod(local_front_state, sample_uv, 0.0).rg;
        // The no-extra-wave estuary peaks below 0.0032; keep the visual
        // splats aligned with the existing front-band source's quiet gate.
        // Foam texture is already motion driven. Keep a broad front envelope
        // and let each fragment's foam/depth sample select the short-lived dots.
        front_activity = 1.0 - smoothstep(3.0, 14.0,
            abs(candidate_cell - local_front.x));
    }
    float width = splat_half_width_m;
    if (target_diameter_px > 0.0) {
        float view_depth = max(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z, 0.1);
        width = min(0.04, view_depth * target_diameter_px /
            (PROJECTION_MATRIX[1][1] * viewport_height_px));
    }
    VERTEX.xz += (UV2 * 2.0 - vec2(1.0)) * width * variation + jitter;
    domain_uv = clamp((VERTEX.xz + vec2(16.0)) / 32.0,
        vec2(0.0), vec2(1.0));
    vec2 surface = surface_at(domain_uv);
    VERTEX.y = surface.x + surface.y + surface_bias_m +
        local_crest(domain_uv, surface.y);
    splat_uv = UV2;
}

void fragment() {
    // Recheck every fragment against wet coverage so a center on water cannot
    // paint across a nearby dry bank.
    float depth = max(texture(water_state, domain_uv).r, 0.0);
    if (depth < 0.008 || splat_seed < 0.22 || front_activity < 0.01) {
        discard;
    }
    float foam = texture(foam_state, domain_uv).r;
    float strength = smoothstep(0.025, 0.28, foam);
    vec2 p = splat_uv * 2.0 - vec2(1.0);
    p.x *= mix(0.7, 1.5, splat_seed);
    float radius = dot(p, p);
    float shape = 1.0 - smoothstep(0.20, 1.0, radius);
    float breakup = hash21(floor(domain_uv * 1024.0) +
        floor(splat_seed * 37.0));
    ALBEDO = mix(vec3(0.67, 0.89, 0.91), vec3(0.96, 0.97, 0.95),
        0.65 + 0.35 * breakup);
    ALPHA = shape * strength * front_activity *
        mix(0.55, 0.95, breakup);
    vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    NORMAL = dot(face, VIEW) < 0.0 ? -face : face;
    natural_foam_color = ALBEDO;
    EMISSION = ALBEDO * (1.0 - natural_foam_direct_fraction);
    ALBEDO = vec3(1.0);
    SPECULAR = 0.0;
    if (natural_lighting_debug > 0) {
        EMISSION = vec3(0.0);
    }
    if (natural_lighting_debug == 2) {
        if (ALPHA < 0.05) { discard; }
        ALPHA = 1.0;
    }

}

void light() {
    if (LIGHT_IS_DIRECTIONAL) {
        if (natural_lighting_debug == 2) {
            DIFFUSE_LIGHT += vec3(ATTENUATION);
        } else {
            DIFFUSE_LIGHT += natural_foam_color * natural_foam_direct_fraction *
                max(dot(NORMAL, LIGHT), 0.0) * LIGHT_COLOR / PI * ATTENUATION;
        }
    }
}
