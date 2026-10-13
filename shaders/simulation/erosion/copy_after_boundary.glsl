#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D sand_in;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D sediment_in;
layout(r32f, set = 0, binding = 2) uniform restrict writeonly image2D sand_out;
layout(r32f, set = 0, binding = 3) uniform restrict writeonly image2D sediment_out;

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(sand_in);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    imageStore(sand_out, p, imageLoad(sand_in, p));
    imageStore(sediment_out, p, imageLoad(sediment_in, p));
}
