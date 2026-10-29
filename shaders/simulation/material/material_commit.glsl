#[compute]
#version 450

// T05 commit step.
//
// wetness, compaction and sand live in the water solver's ping-pong arrays, but
// only the water solver advances that index. The material passes therefore write
// the spare slot and this pass copies the spare slot back onto the live one, so
// whichever slot the solver is reading always holds the newest material state.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r16f, set = 0, binding = 0) uniform restrict readonly image2D wetness_src;
layout(r16f, set = 0, binding = 1) uniform restrict readonly image2D compaction_src;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D sand_src;
layout(r16f, set = 0, binding = 3) uniform restrict writeonly image2D wetness_dst;
layout(r16f, set = 0, binding = 4) uniform restrict writeonly image2D compaction_dst;
layout(r32f, set = 0, binding = 5) uniform restrict writeonly image2D sand_dst;

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(wetness_src);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    imageStore(wetness_dst, p, vec4(imageLoad(wetness_src, p).r, 0.0, 0.0, 1.0));
    imageStore(compaction_dst, p, vec4(imageLoad(compaction_src, p).r, 0.0, 0.0, 1.0));
    imageStore(sand_dst, p, vec4(imageLoad(sand_src, p).r, 0.0, 0.0, 1.0));
}
