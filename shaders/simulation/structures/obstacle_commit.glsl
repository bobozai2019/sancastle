#[compute]
#version 450

// T06 obstacle remap commit.
//
// The remap pass reads the water/momentum/sediment slot the solver is live on, so
// it has to write the spare one (a texture cannot be read and written by the same
// dispatch). This copies the spare result back onto the live slot, leaving both
// slots identical so the solver may flip the index at any time.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D water_src;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D momentum_x_src;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D momentum_z_src;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D sediment_src;
layout(r32f, set = 0, binding = 4) uniform restrict writeonly image2D water_dst;
layout(r32f, set = 0, binding = 5) uniform restrict writeonly image2D momentum_x_dst;
layout(r32f, set = 0, binding = 6) uniform restrict writeonly image2D momentum_z_dst;
layout(r32f, set = 0, binding = 7) uniform restrict writeonly image2D sediment_dst;

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(water_src);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    imageStore(water_dst, p, vec4(imageLoad(water_src, p).r, 0.0, 0.0, 1.0));
    imageStore(momentum_x_dst, p, vec4(imageLoad(momentum_x_src, p).r, 0.0, 0.0, 1.0));
    imageStore(momentum_z_dst, p, vec4(imageLoad(momentum_z_src, p).r, 0.0, 0.0, 1.0));
    imageStore(sediment_dst, p, vec4(imageLoad(sediment_src, p).r, 0.0, 0.0, 1.0));
}
