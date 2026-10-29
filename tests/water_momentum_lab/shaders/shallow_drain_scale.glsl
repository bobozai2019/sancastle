#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D water_state;
layout(rgba32f, set = 0, binding = 1) uniform restrict readonly image2D edge_x_state;
layout(rgba32f, set = 0, binding = 2) uniform restrict readonly image2D edge_z_state;
layout(r32f, set = 0, binding = 3) uniform restrict writeonly image2D drain_scale_out;

layout(set = 0, binding = 15, std430) readonly buffer Params {
    float delta_over_cell_size;
    float reserved0;
    float reserved1;
    float reserved2;
} params;

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(water_state);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    float outgoing = 0.0;
    if (p.x + 1 < extent.x) {
        outgoing += max(imageLoad(edge_x_state, p).r, 0.0);
    }
    if (p.x > 0) {
        outgoing += max(-imageLoad(edge_x_state, p + ivec2(-1, 0)).r, 0.0);
    }
    if (p.y + 1 < extent.y) {
        outgoing += max(imageLoad(edge_z_state, p).r, 0.0);
    }
    if (p.y > 0) {
        outgoing += max(-imageLoad(edge_z_state, p + ivec2(0, -1)).r, 0.0);
    }
    float depth = max(imageLoad(water_state, p).r, 0.0);
    float requested_depth = params.delta_over_cell_size * outgoing;
    float scale = requested_depth > depth ? depth / max(requested_depth, 0.000000001) : 1.0;
    imageStore(drain_scale_out, p, vec4(scale, 0.0, 0.0, 1.0));
}
