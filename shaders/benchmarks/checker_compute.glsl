#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict writeonly image2D output_image;

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    float value = ((pixel.x / 8 + pixel.y / 8) % 2 == 0) ? 1.0 : 0.25;
    imageStore(output_image, pixel, vec4(value, 0.0, 0.0, 1.0));
}
