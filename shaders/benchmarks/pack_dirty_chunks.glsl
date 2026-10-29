#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D source_image;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D packed_image;

layout(push_constant, std430) uniform Params {
    ivec4 values;
} params;

void main() {
    ivec2 destination = ivec2(gl_GlobalInvocationID.xy);
    int chunk = destination.y / 32;
    if (destination.x >= 32 || chunk >= params.values.z) {
        return;
    }
    ivec2 local_pixel = ivec2(destination.x, destination.y % 32);
    ivec2 source_origin = params.values.xy + ivec2(chunk % 4, chunk / 4) * 32;
    float height = imageLoad(source_image, source_origin + local_pixel).r;
    imageStore(packed_image, destination, vec4(height, 0.0, 0.0, 1.0));
}
