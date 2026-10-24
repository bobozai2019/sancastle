#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2D x_field;
layout(rg32f, set = 0, binding = 1) uniform restrict writeonly image2D local_front_out;

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p, ivec2(256)))) {
        return;
    }
    float sum_weight = 0.0;
    float sum_x_weight = 0.0;
    float peak = 0.0;
    for (int dz = -4; dz <= 4; dz++) {
        ivec2 q = clamp(p + ivec2(0, dz), ivec2(0), ivec2(255));
        vec3 x = imageLoad(x_field, q).rgb;
        float window = 1.0 - float(abs(dz)) / 5.0;
        sum_weight += x.x * window;
        sum_x_weight += x.y * window;
        peak = max(peak, x.z * window);
    }
    float front_x = sum_weight > 1e-12 ? sum_x_weight / sum_weight : 0.0;
    imageStore(local_front_out, p, vec4(front_x, peak, 0.0, 1.0));
}
