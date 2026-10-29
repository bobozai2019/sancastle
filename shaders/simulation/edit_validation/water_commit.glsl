#[compute]
#version 450
layout(local_size_x=64) in;
struct InputCell { vec4 bed_water; vec4 flow; };
layout(set=0,binding=0,std430) readonly buffer Input { InputCell input_cells[]; };
layout(set=0,binding=1,std430) readonly buffer Candidate { vec4 output_cells[]; };
layout(set=0,binding=2,std430) readonly buffer EditReceipt { uint r[]; };
layout(r32f,set=0,binding=3) uniform writeonly image2D h0;
layout(r32f,set=0,binding=4) uniform writeonly image2D h1;
layout(r32f,set=0,binding=5) uniform writeonly image2D s0;
layout(r32f,set=0,binding=6) uniform writeonly image2D s1;
layout(r32f,set=0,binding=7) uniform writeonly image2D x0;
layout(r32f,set=0,binding=8) uniform writeonly image2D x1;
layout(r32f,set=0,binding=9) uniform writeonly image2D z0;
layout(r32f,set=0,binding=10) uniform writeonly image2D z1;
layout(push_constant,std430) uniform Params { uint size; uint rollback; uint pad0; uint pad1; } params;
void main() {
    uint i=gl_GlobalInvocationID.x,n=params.size;
    if(i>=n*n||(params.rollback==0u&&r[12]!=1u)) return;
    vec4 value=params.rollback!=0u?vec4(input_cells[i].bed_water.zw,input_cells[i].flow.xy):output_cells[i];
    ivec2 p=ivec2(i%n,i/n);
    imageStore(h0,p,vec4(value.x));imageStore(h1,p,vec4(value.x));
    imageStore(s0,p,vec4(value.y));imageStore(s1,p,vec4(value.y));
    imageStore(x0,p,vec4(value.z));imageStore(x1,p,vec4(value.z));
    imageStore(z0,p,vec4(value.w));imageStore(z1,p,vec4(value.w));
}
