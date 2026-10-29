#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D sand_state;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D sediment_state;
layout(rgba32f, set = 0, binding = 2) uniform restrict writeonly image2D audit_tiles_out;

layout(push_constant, std430) uniform Params {
    float cell_area_m2;
    float reserved_0;
    float reserved_1;
    float reserved_2;
} params;

shared vec4 tile_stats[64];

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    uint local_index = gl_LocalInvocationID.y * 8u + gl_LocalInvocationID.x;
    float sand = imageLoad(sand_state, p).r;
    float sediment = imageLoad(sediment_state, p).r;
    bool invalid = isnan(sand) || isinf(sand) || isnan(sediment) || isinf(sediment);
    tile_stats[local_index] = vec4(
        invalid ? 0.0 : sand * params.cell_area_m2,
        invalid ? 0.0 : sediment * params.cell_area_m2,
        invalid ? 1.0 : 0.0,
        (!invalid && (sand < -0.000001 || sediment < -0.000001)) ? 1.0 : 0.0);
    barrier();
    for (uint stride = 32u; stride > 0u; stride >>= 1u) {
        if (local_index < stride) {
            tile_stats[local_index] += tile_stats[local_index + stride];
        }
        barrier();
    }
    if (local_index == 0u) {
        imageStore(audit_tiles_out, ivec2(gl_WorkGroupID.xy), tile_stats[0]);
    }
}
