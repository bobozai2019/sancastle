shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// W07 local-front closed section: intersect the raised main surface at one
// wet, locally supported crest per row rather than drawing the old long tube.
uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D rise_front_state : filter_nearest, repeat_disable;
uniform sampler2D local_front_state : filter_linear, repeat_disable;
uniform bool display_reconstruction = true;
uniform float radius_x_m = 0.30;
uniform float radius_y_m = 0.18;
uniform bool layer_debug = false;
varying float crest_t;
varying float crest_mask;

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

void vertex() {
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
    float front_x = position_weight > 1e-10 ?
        position_sum / position_weight : 0.0;
    front_x = clamp(front_x, 112.0, 248.0);
    vec2 local_front = textureLod(local_front_state,
        vec2((front_x + 0.5) / 256.0, UV.y), 0.0).rg;
    if (local_front.y > 0.0001) {
        front_x = clamp(local_front.x, 0.0, 255.0);
    }
    vec2 front_uv = vec2((front_x + 0.5) / 256.0, UV.y);
    vec2 surface = surface_at(front_uv);
    crest_mask = smoothstep(0.0020, 0.0045, support) *
        smoothstep(0.0020, 0.0050, local_front.y) *
        smoothstep(0.04, 0.12, surface.y);
    float wet_toe_m = 0.58;
    for (int sample_step = 1; sample_step <= 5; sample_step++) {
        float sample_x = clamp(front_x + float(sample_step), 0.0, 255.0);
        float sample_depth = max(textureLod(water_state,
            vec2((sample_x + 0.5) / 256.0, UV.y), 0.0).r, 0.0);
        if (sample_depth < 0.01) {
            wet_toe_m = max(0.04, float(sample_step - 1) * 0.125);
            break;
        }
    }
    float rx = min(radius_x_m, wet_toe_m) * crest_mask;
    float ry = min(radius_y_m, surface.y * 0.75) * crest_mask;
    float angle = UV.x * 6.28318530718;
    float center_x_m = (front_x + 0.5) * 0.125 - 16.0;
    VERTEX.x = center_x_m + cos(angle) * rx;
    VERTEX.y = surface.x + surface.y + 0.006 + ry *
        (1.0 + sin(angle));
    crest_t = UV.x;
}

void fragment() {
    if (crest_mask < 0.02) {
        discard;
    }
    float frontness = max(cos(crest_t * 6.28318530718), 0.0);
    float upper = max(sin(crest_t * 6.28318530718), 0.0);
    ALBEDO = mix(vec3(0.045, 0.32, 0.41),
        vec3(0.19, 0.65, 0.70), 0.55 * frontness + 0.45 * upper);
    if (layer_debug) {
        ALBEDO = frontness > 0.55 ? vec3(0.93, 0.60, 0.13) :
            upper > 0.55 ? vec3(0.15, 0.86, 0.24) :
            vec3(0.18, 0.28, 0.95);
    }
}
