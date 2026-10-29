#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Cells {uint v[];};
layout(set=0,binding=1,std430) readonly buffer Receipt {uint r[];};
struct InputCell {vec4 bed_water;vec4 flow;};
layout(set=0,binding=2,std430) writeonly buffer Input {InputCell inputs[];};
layout(set=1,binding=0,r32f) uniform readonly image2D water0;
layout(set=1,binding=1,r32f) uniform readonly image2D water1;
layout(set=1,binding=2,r32f) uniform readonly image2D sediment0;
layout(set=1,binding=3,r32f) uniform readonly image2D sediment1;
layout(set=1,binding=4,r32f) uniform readonly image2D qx0;
layout(set=1,binding=5,r32f) uniform readonly image2D qx1;
layout(set=1,binding=6,r32f) uniform readonly image2D qz0;
layout(set=1,binding=7,r32f) uniform readonly image2D qz1;
layout(set=1,binding=8,r8) uniform readonly image2D obstacle;
layout(push_constant,std430) uniform Push {uint n,index,phase,policy,pad0,pad1,pad2,pad3;}p;
void main(){uint i=gl_GlobalInvocationID.x;if(i>=p.n*p.n)return;uint k=i*16u;ivec2 q=ivec2(i%p.n,i/p.n);
 float old=uintBitsToFloat(v[k]),next=r[3]==1u?uintBitsToFloat(v[k+1u]):old,rock=uintBitsToFloat(v[k+2u]);
 float h=p.index==0u?imageLoad(water0,q).x:imageLoad(water1,q).x;
 float sed=p.index==0u?imageLoad(sediment0,q).x:imageLoad(sediment1,q).x;
 float x=p.index==0u?imageLoad(qx0,q).x:imageLoad(qx1,q).x;
 float z=p.index==0u?imageLoad(qz0,q).x:imageLoad(qz1,q).x;
 inputs[i].bed_water=vec4(rock+old,rock+next,h,sed);inputs[i].flow=vec4(x,z,imageLoad(obstacle,q).x,0);
}
