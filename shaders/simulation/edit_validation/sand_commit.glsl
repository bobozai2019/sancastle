#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) readonly buffer Cells { vec4 cells[]; };
layout(set=0,binding=3,std430) buffer Receipt { uint r[]; };
layout(r32f,set=0,binding=4) uniform writeonly image2D sand_0;
layout(r32f,set=0,binding=5) uniform writeonly image2D sand_1;
layout(push_constant,std430) uniform Params { uint rollback; uint x; uint z; uint width; uint height; uint pad0; uint pad1; uint pad2; } params;
void main() {
    uint lane=gl_GlobalInvocationID.x,n=c[20];
    if(lane>=params.width*params.height) return;
    uint i=(params.z+lane/params.width)*n+params.x+lane%params.width;
    if(params.rollback!=0u&&lane==0u) {
        r[12]=2u; r[13]=6u; r[14]=0u; r[8]=c[8]; r[9]=c[9];
        for(uint j=16u;j<=21u;j++) r[j]=0u;
        r[24]=0u;
    }
    if((params.rollback==0u&&r[12]!=1u)||cells[i].x<=0.0) return;
    ivec2 p=ivec2(i%n,i/n);
    float value=params.rollback!=0u?cells[i].z:cells[i].y;
    imageStore(sand_0,p,vec4(value));
    imageStore(sand_1,p,vec4(value));
}
