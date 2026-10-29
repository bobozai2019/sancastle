#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) buffer Cells { vec4 cells[]; };
layout(set=0,binding=2,std430) readonly buffer State { uint s[]; };
layout(set=0,binding=3,std430) readonly buffer Receipt { uint r[]; };
layout(push_constant,std430) uniform Params { uint mode; uint x; uint z; uint width; uint height; uint pad0; uint pad1; uint pad2; } params;
void main() {
    uint lane=gl_GlobalInvocationID.x,n=c[20];
    if(lane>=params.width*params.height||r[12]!=1u) return;
    uint i=(params.z+lane/params.width)*n+params.x+lane%params.width;
    cells[i].w=0.0;
    float weight=cells[i].x;
    if(weight<=0.0) return;
    float area=uintBitsToFloat(c[19])*uintBitsToFloat(c[19]);
    if(c[10]==1u) {
        float amount=uintBitsToFloat(s[0])*weight/uintBitsToFloat(s[2]);
        cells[i].y=cells[i].z+amount/area;
        cells[i].w=amount;
    } else {
        float remaining=uintBitsToFloat(s[1]),active_weight=uintBitsToFloat(s[3]);
        if(remaining<=uintBitsToFloat(c[22])||active_weight<=uintBitsToFloat(c[22])) return;
        float take=min(cells[i].y*area,remaining*weight/active_weight);
        cells[i].y-=take/area;
        cells[i].w=take;
    }
}
