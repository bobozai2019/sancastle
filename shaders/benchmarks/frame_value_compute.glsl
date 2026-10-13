#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
    float value;
    float reserved0;
    float reserved1;
    float reserved2;
} params;

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    imageStore(output_image, pixel, vec4(params.value, 0.0, 0.0, 1.0));
}
