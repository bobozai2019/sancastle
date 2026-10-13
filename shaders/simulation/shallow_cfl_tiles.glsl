#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D water_state;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D momentum_x_state;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D momentum_z_state;
layout(r32f, set = 0, binding = 3) uniform restrict writeonly image2D tile_max_out;

shared float wave_speeds[64];

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(water_state);
    uint local_index = gl_LocalInvocationID.y * 8u + gl_LocalInvocationID.x;
    float speed = 0.01;
    if (p.x < extent.x && p.y < extent.y) {
        float h = imageLoad(water_state, p).r;
        if (h > 0.001) {
            float qx = imageLoad(momentum_x_state, p).r;
            float qz = imageLoad(momentum_z_state, p).r;
            speed = max(abs(qx), abs(qz)) / max(h, 0.005) + sqrt(9.81 * h);
        }
    }
    wave_speeds[local_index] = speed;
    barrier();
    for (uint stride = 32u; stride > 0u; stride >>= 1u) {
        if (local_index < stride) {
            wave_speeds[local_index] = max(wave_speeds[local_index],
                wave_speeds[local_index + stride]);
        }
        barrier();
    }
    if (local_index == 0u) {
        imageStore(tile_max_out, ivec2(gl_WorkGroupID.xy), vec4(wave_speeds[0]));
    }
}
