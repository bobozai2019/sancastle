#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) readonly buffer StagedSlope { uvec2 result_bits[]; };
layout(r32f,set=0,binding=1) uniform writeonly image2D sand_out;
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy),extent=imageSize(sand_out);
    if(p.x>=extent.x||p.y>=extent.y) return;
    float value=uintBitsToFloat(result_bits[uint(p.y*extent.x+p.x)].y);
    imageStore(sand_out,p,vec4(max(value,0.0),0.0,0.0,1.0));
}
