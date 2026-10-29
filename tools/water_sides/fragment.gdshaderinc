// An exterior cut face, not an extra horizontal water layer. Only the outward
// facing side is composited, so the rear wall cannot absorb the same ray twice.
float side_exit_axis(float p, float direction, float low, float high) {
    if (abs(direction) < 0.00001) return 10000.0;
    return max(((direction > 0.0 ? high : low) - p) / direction, 0.0);
}

void fragment() {
    vec3 surface = display_surface(UV);
    if (surface.y <= wet_epsilon_m || side_top_y <= side_bottom_y) discard;
    if (side_debug == 1) {
        ALBEDO = vec3(0.9, 0.08, 0.6);
        ALPHA = 1.0;
    } else {
        vec3 ray = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
        float path_length = min(
            side_exit_axis(side_position.x, ray.x, side_min_xz.x, side_max_xz.x),
            side_exit_axis(side_position.z, ray.z, side_min_xz.y, side_max_xz.y));
        // Local surface plane is a bounded approximation for rays leaving upward.
        // Opaque scene depth supplies the actual visible bed/object intersection.
        if (ray.y > 0.00001) {
            path_length = min(path_length, max((side_top_y - side_position.y) / ray.y, 0.0));
        }
        float raw_depth = textureLod(prototype_scene_depth, SCREEN_UV, 0.0).r;
        vec4 opaque_h = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
        if (raw_depth > 0.000001 && abs(opaque_h.w) > 0.000001) {
            vec3 opaque_position = opaque_h.xyz / opaque_h.w;
            float opaque_distance = dot(opaque_position - VERTEX, normalize(-VIEW));
            if (opaque_distance > 0.0) path_length = min(path_length, opaque_distance);
        }
        path_length = clamp(path_length, 0.0, 50.0);
        float t = use_async_clock ? textureLod(async_clock, vec2(0.5), 0.0).r : max(visual_time_s, 0.0);
        vec3 n = normalize(NORMAL);
        float ripple = sin(dot(side_position.xz, vec2(3.1, 2.7)) + side_position.y * 3.0 - t * 0.65);
        vec2 offset = n.xy * (0.0007 + 0.0002 * ripple) * smoothstep(0.0, 0.15, path_length);
        vec2 sample_uv = clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999));
        float shifted_depth = textureLod(prototype_scene_depth, sample_uv, 0.0).r;
        vec4 shifted_h = INV_PROJECTION_MATRIX * vec4(sample_uv * 2.0 - 1.0, shifted_depth, 1.0);
        if (abs(shifted_h.w) > 0.000001 && shifted_depth > 0.000001 && -shifted_h.z / shifted_h.w <= -VERTEX.z + 0.005) sample_uv = SCREEN_UV;
        vec3 background = textureLod(prototype_scene_color, sample_uv, 0.0).rgb;
        vec3 transmission = exp(-path_length * rdc_distance_scale * rdc_absorption_rgb);
        vec3 color = background * mix(vec3(1.0), rdc_transmission_tint, smoothstep(0.0, 0.15, path_length)) * transmission;
        color += side_scatter_color * (vec3(1.0) - transmission);
        float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), n), 0.0, 1.0), 5.0);
        color = mix(color, vec3(0.55, 0.75, 0.86), 0.06 * fresnel);
        ALBEDO = color;
        // Background transmission is already in color; alpha blending again
        // would double the background and expose the far side through this face.
        ALPHA = 1.0;
    }
}
