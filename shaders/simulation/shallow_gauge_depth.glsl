#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D water_state;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D gauge_depth_out;

layout(push_constant, std430) uniform Params {
    ivec4 position;
} params;

void main() {
    float h = imageLoad(water_state, params.position.xy).r;
    imageStore(gauge_depth_out, ivec2(0, 0), vec4(h, 0.0, 0.0, 1.0));
}
