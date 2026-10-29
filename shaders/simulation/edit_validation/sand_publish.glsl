#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(r32f,set=0,binding=4) uniform readonly image2D sand_in;
layout(r32f,set=0,binding=6) uniform writeonly image2D sand_out;
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(p,imageSize(sand_in)))) return;
    imageStore(sand_out,p,imageLoad(sand_in,p));
}
