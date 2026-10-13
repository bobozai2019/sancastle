shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// W07 connected single-front trial. Adjacent coastline rows share vertices;
// inactive rows taper the extra height back into the existing water surface.
uniform sampler2D rock_state : filter_nearest, repeat_disable;
uniform sampler2D sand_state : filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_nearest, repeat_disable;
uniform sampler2D local_front_state : filter_linear, repeat_disable;
uniform sampler2D rise_front_state : filter_nearest, repeat_disable;
uniform bool display_reconstruction = true;
uniform bool prototype_branch_face = false;
uniform bool prototype_branch_face_capped = false;
uniform bool prototype_branch_face_2d = false;
uniform bool prototype_branch_face_row_center = false;
uniform bool prototype_branch_face_soft_material = false;
uniform bool prototype_branch_face_surface_join = false;
varying float segment_mask;
varying float segment_layer;
varying vec2 branch_sample_uv;

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

float main_crest(vec2 uv, float depth) {
    vec2 front = textureLod(local_front_state, uv, 0.0).rg;
    float distance_cells = uv.x * 256.0 - 0.5 - front.x;
    float shoulder = smoothstep(-7.5, -1.0, distance_cells);
    float face = 1.0 - smoothstep(0.0, 1.8, distance_cells);
    float lift = 0.25 * smoothstep(0.0012, 0.0045, front.y) *
        shoulder * face * smoothstep(0.012, 0.065, depth);
    return min(lift, max(depth, 0.0) * 1.5);
}

vec2 profile_point(int layer) {
    if (layer == 1) return vec2(-0.45, 0.25);
    if (layer == 2) return vec2(-0.26, 0.65);
    if (layer == 3) return vec2(-0.08, 1.00);
    if (layer == 4) return vec2(0.06, 1.15);
    if (layer == 5) return vec2(0.18, 0.90);
    if (layer == 6) return vec2(0.08, 0.55);
    if (layer == 7) return vec2(0.14, 0.18);
    if (layer == 8) return vec2(0.28, 0.0);
    return vec2(-0.65, 0.0);
}

void vertex() {
    vec2 row_front = textureLod(rise_front_state, vec2(UV.y, 0.5), 0.0).rg;
    float sum_weight = 0.0;
    float sum_position = 0.0;
    float neighbor_peak = 0.0;
    for (int dz = -2; dz <= 2; dz++) {
        float row_uv = clamp(UV.y + float(dz) / 256.0, 0.0, 1.0);
        vec2 nearby = textureLod(rise_front_state, vec2(row_uv, 0.5), 0.0).rg;
        float weight = smoothstep(0.001, 0.004, nearby.y) *
            (1.0 - float(abs(dz)) / 3.0);
        sum_weight += weight;
        sum_position += weight * nearby.x;
        if (abs(dz) == 1) {
            neighbor_peak = max(neighbor_peak, nearby.y);
        }
    }
    float front_cell = sum_weight > 0.001 ? sum_position / sum_weight : 180.0;
    float local_peak = 0.0;
    float selected = 1.0;
    if (prototype_branch_face_2d) {
        vec2 local = textureLod(local_front_state, UV2, 0.0).rg;
        float candidate_cell = UV2.x * 256.0 - 0.5;
        front_cell = local.y > 0.0001 ? local.x : candidate_cell;
        local_peak = local.y;
        selected = 1.0 - step(2.0, abs(front_cell - candidate_cell));
    } else if (prototype_branch_face_row_center) {
        // One branch center per row for fields whose active X support is
        // connected; the local 2D field decides whether this row is active.
        front_cell = row_front.x;
    }
    vec2 center_uv = vec2((front_cell + 0.5) / 256.0, UV.y);
    vec2 center_surface = surface_at(center_uv);
    vec2 local_front = textureLod(local_front_state, center_uv, 0.0).rg;
    float forward_depth = max(textureLod(water_state,
        vec2((min(front_cell + 3.0, 255.0) + 0.5) / 256.0,
            UV.y), 0.0).r, 0.0);
    segment_mask = smoothstep(0.0015, 0.0045,
        max(row_front.y, neighbor_peak * 0.55)) *
        smoothstep(0.001, 0.0035, local_front.y) *
        smoothstep(0.01, 0.05, forward_depth) *
        smoothstep(0.04, 0.12, center_surface.y);
    if (prototype_branch_face_2d) {
        segment_mask = selected * smoothstep(0.0015, 0.0045, local_peak) *
            smoothstep(0.01, 0.05, forward_depth) *
            smoothstep(0.04, 0.12, center_surface.y);
    } else if (prototype_branch_face_row_center) {
        segment_mask = smoothstep(0.0015, 0.0045, local_front.y) *
            smoothstep(0.01, 0.05, forward_depth) *
            smoothstep(0.04, 0.12, center_surface.y);
    }
    if (prototype_branch_face && !prototype_branch_face_2d &&
            !prototype_branch_face_row_center) {
        // Reject isolated one-row rises. The estuary's real branches span
        // many rows, while still water can produce a lone 0.003 peak.
        int supported_rows = 0;
        for (int dz = -2; dz <= 2; dz++) {
            float row_uv = clamp(UV.y + float(dz) / 256.0,
                0.5 / 256.0, 255.5 / 256.0);
            vec2 neighbor = textureLod(rise_front_state,
                vec2(row_uv, 0.5), 0.0).rg;
            supported_rows += neighbor.y >= 0.003 ? 1 : 0;
        }
        segment_mask *= step(3.0, float(supported_rows));
    }
    float cap = 1.0;
    if (prototype_branch_face_capped) {
        int z = clamp(int(floor(UV.y * 256.0)), 0, 255);
        int to_edge = 5;
        for (int dz = 1; dz <= 4; dz++) {
            if (z - dz >= 0) {
                float earlier_peak = prototype_branch_face_2d ?
                    texelFetch(local_front_state,
                        ivec2(clamp(int(floor(UV2.x * 256.0)), 0, 255), z - dz), 0).g :
                    prototype_branch_face_row_center ?
                    textureLod(local_front_state, vec2(
                        (texelFetch(rise_front_state, ivec2(z - dz, 0), 0).r + 0.5) / 256.0,
                        (float(z - dz) + 0.5) / 256.0), 0.0).g :
                    texelFetch(rise_front_state, ivec2(z - dz, 0), 0).g;
                if (earlier_peak < 0.003) {
                    to_edge = min(to_edge, dz);
                    break;
                }
            }
        }
        for (int dz = 1; dz <= 4; dz++) {
            if (z + dz < 256) {
                float later_peak = prototype_branch_face_2d ?
                    texelFetch(local_front_state,
                        ivec2(clamp(int(floor(UV2.x * 256.0)), 0, 255), z + dz), 0).g :
                    prototype_branch_face_row_center ?
                    textureLod(local_front_state, vec2(
                        (texelFetch(rise_front_state, ivec2(z + dz, 0), 0).r + 0.5) / 256.0,
                        (float(z + dz) + 0.5) / 256.0), 0.0).g :
                    texelFetch(rise_front_state, ivec2(z + dz, 0), 0).g;
                if (later_peak < 0.003) {
                    to_edge = min(to_edge, dz);
                    break;
                }
            }
        }
        cap = smoothstep(1.0, 4.0, float(to_edge));
        segment_mask *= cap;
    }
    float amplitude = min(0.25, center_surface.y * 1.5) * segment_mask;
    int layer = clamp(int(round(UV.x * 8.0)), 0, 8);
    vec2 shape = profile_point(layer);
    float front_m = (front_cell + 0.5) * 0.125 - 16.0;
    float width = prototype_branch_face ? 0.60 : 0.32;
    if (prototype_branch_face_capped) {
        width *= mix(0.12, 1.0, cap);
    }
    float x_m = front_m + shape.x * width;
    vec2 sample_uv = vec2(clamp((x_m + 16.0) / 32.0, 0.0, 1.0), UV.y);
    branch_sample_uv = sample_uv;
    vec2 surface = surface_at(sample_uv);
    float extra = layer == 0 || layer == 8 ? 0.0 :
        amplitude * (prototype_branch_face ? 1.0 : 0.18) * shape.y;
    VERTEX.x = x_m;
    if (prototype_branch_face_surface_join) {
        // Both ends meet the displaced main water surface. The interior only
        // rises above it where the folded section actually adds height.
        float main_height = main_crest(sample_uv, surface.y);
        VERTEX.y = surface.x + surface.y + 0.003 +
            max(main_height, extra);
    } else {
        VERTEX.y = surface.x + surface.y + 0.006 +
            (prototype_branch_face ? 0.0 : main_crest(sample_uv, surface.y)) + extra;
    }
    segment_layer = UV.x;
}

void fragment() {
    if (segment_mask < 0.02) {
        discard;
    }
    if ((prototype_branch_face_capped || prototype_branch_face_2d ||
            prototype_branch_face_row_center) &&
            texture(water_state, branch_sample_uv).r < 0.008) {
        discard;
    }
    if (prototype_branch_face_soft_material) {
        vec3 face_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
        float facing = abs(dot(face_normal, normalize(VIEW)));
        float rim = pow(1.0 - clamp(facing, 0.0, 1.0), 3.0);
        float crown_soft = smoothstep(0.15, 0.37, segment_layer) *
            (1.0 - smoothstep(0.68, 0.90, segment_layer));
        vec2 grain_cell = floor(vec2(UV.y * 90.0, segment_layer * 8.0));
        float grain = fract(sin(dot(grain_cell, vec2(12.9898, 78.233))) *
            43758.5453);
        float foam = crown_soft * (0.35 + 0.65 * smoothstep(0.23, 0.72, grain));
        ALBEDO = mix(vec3(0.025, 0.32, 0.39),
            vec3(0.86, 0.94, 0.96), clamp(foam + rim * 0.12, 0.0, 1.0));
        ALPHA = clamp(0.30 + 0.18 * rim + 0.52 * foam, 0.0, 0.95);
    } else {
        float crown = smoothstep(0.18, 0.43, segment_layer) *
            (1.0 - smoothstep(0.70, 0.91, segment_layer));
        float broken = 0.55 + 0.45 * sin(UV.y * 873.0 + segment_layer * 23.0) *
            sin(UV.y * 397.0 - segment_layer * 31.0);
        float white = crown * smoothstep(0.18, 0.72, broken);
        ALBEDO = mix(vec3(0.015, 0.25, 0.32),
            vec3(0.93, 0.96, 0.97), white * 0.88);
    }
}
