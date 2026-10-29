#[compute]
#version 450
layout(local_size_x=16,local_size_y=16) in;
layout(set=0,binding=1,std430) readonly buffer Receipt {uint r[];};
layout(set=0,binding=2,std430) readonly buffer Cells {uint v[];};
layout(set=0,binding=5,rg32f) uniform writeonly image2D coverage;
layout(set=0,binding=6,rg32f) uniform readonly image2D candidate;
layout(set=1,binding=1,r32f) uniform image2D sand0;
layout(set=1,binding=2,r32f) uniform image2D sand1;
layout(push_constant,std430) uniform Push {uint n,x,z,w,h,index,phase,reserved;}p;
void main(){ivec2 q=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(q,ivec2(p.n)))||r[3]==3u)return;uint i=uint(q.y)*p.n+uint(q.x);if(r[3]==1u&&v[i*16u]!=v[i*16u+1u]){float value=uintBitsToFloat(v[i*16u+1u]);imageStore(sand0,q,vec4(value));imageStore(sand1,q,vec4(value));}imageStore(coverage,q,imageLoad(candidate,q));}
