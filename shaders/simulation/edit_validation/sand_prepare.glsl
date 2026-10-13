#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) buffer Cells { vec4 cells[]; };
layout(r32f,set=0,binding=4) uniform readonly image2D sand_in;
layout(push_constant,std430) uniform Params { uint mode; uint x; uint z; uint width; uint height; uint pad0; uint pad1; uint pad2; } params;
void main() {
    uint n=c[20], lane=gl_GlobalInvocationID.x;
    if(lane>=params.width*params.height) return;
    uint i=(params.z+lane/params.width)*n+params.x+lane%params.width;
    vec2 p=(vec2(i%n,i/n)+0.5-float(n)*0.5)*uintBitsToFloat(c[19]);
    vec2 a=vec2(uintBitsToFloat(c[12]),uintBitsToFloat(c[13]));
    vec2 b=c[11]==0u?a:vec2(uintBitsToFloat(c[14]),uintBitsToFloat(c[15]));
    vec2 segment=b-a;
    float l2=dot(segment,segment);
    vec2 closest=a;
    if(l2>1e-6) closest+=segment*clamp(dot(p-a,segment)/l2,0.0,1.0);
    float distance=length(p-closest), radius=uintBitsToFloat(c[16]);
    float w=distance<=radius?max(0.001,1.0-distance/radius):0.0;
    float before=imageLoad(sand_in,ivec2(i%n,i/n)).r;
    cells[i]=vec4(w,before,before,0.0);
}
