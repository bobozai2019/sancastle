#[compute]
#version 450
layout(local_size_x=16,local_size_y=16) in;
layout(set=0,binding=0,r32f) uniform readonly image2D backupSand0;
layout(set=0,binding=1,r32f) uniform readonly image2D backupSand1;
layout(set=0,binding=2,rg32f) uniform readonly image2D backupCoverage;
layout(set=0,binding=5,rg32f) uniform writeonly image2D coverage;
layout(set=1,binding=1,r32f) uniform writeonly image2D sand0;
layout(set=1,binding=2,r32f) uniform writeonly image2D sand1;
layout(push_constant,std430) uniform Push {uint n,x,z,w,h,index,phase,reserved;}p;
void main(){ivec2 q=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(q,ivec2(p.n))))return;imageStore(sand0,q,imageLoad(backupSand0,q));imageStore(sand1,q,imageLoad(backupSand1,q));imageStore(coverage,q,imageLoad(backupCoverage,q));}
