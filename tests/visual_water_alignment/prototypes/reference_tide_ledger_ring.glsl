#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D tide_delta;
layout(set = 0, binding = 1, std430) buffer LedgerRing {
    float values[];
} ring;

layout(push_constant, std430) uniform Params {
    int slot;
    int grid_size;
    int reserved_0;
    int reserved_1;
} params;

void main() {
    int z = int(gl_GlobalInvocationID.x);
    if (z >= params.grid_size) {
        return;
    }
    ring.values[params.slot * params.grid_size + z] =
        imageLoad(tide_delta, ivec2(0, z)).r;
}
