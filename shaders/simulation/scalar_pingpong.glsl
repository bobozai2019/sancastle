#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D state_in;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D state_out;

void main() {
    ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(state_in);
    if (cell.x >= extent.x || cell.y >= extent.y) {
        return;
    }
    float value = imageLoad(state_in, cell).r;
    imageStore(state_out, cell, vec4(value + 0.001, 0.0, 0.0, 1.0));
}
