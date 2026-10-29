#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D rock_state;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D sand_state;
layout(r32f, set = 0, binding = 2) uniform restrict writeonly image2D packed_heights;
layout(set = 0, binding = 3, std430) restrict readonly buffer ChunkIds {
    int ids[];
} chunks;

layout(push_constant, std430) uniform Params {
    int grid_size;
    int chunks_per_row;
    int count;
    int reserved;
} params;

void main() {
    ivec2 target = ivec2(gl_GlobalInvocationID.xy);
    int slot = target.y / 33;
    if (target.x >= 33 || slot >= params.count) {
        return;
    }
    int chunk_id = chunks.ids[slot];
    ivec2 cell = ivec2(chunk_id % params.chunks_per_row,
        chunk_id / params.chunks_per_row) * 32 + ivec2(target.x, target.y % 33);
    cell = min(cell, ivec2(params.grid_size - 1));
    float bed = imageLoad(rock_state, cell).r + imageLoad(sand_state, cell).r;
    imageStore(packed_heights, target, vec4(bed, 0.0, 0.0, 1.0));
}
