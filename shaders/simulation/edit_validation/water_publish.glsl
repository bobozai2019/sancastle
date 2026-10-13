#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(r32f,set=0,binding=0) uniform readonly image2D source;
layout(r32f,set=0,binding=1) uniform writeonly image2D destination;
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(p,imageSize(source)))) return;
    imageStore(destination,p,imageLoad(source,p));
}
