#[compute]
#version 450
layout(local_size_x=16,local_size_y=16) in;
layout(set=0,binding=1,std430) buffer Marker {uint marker[];};
layout(set=0,binding=4,r32f) uniform writeonly image2D baseline;
layout(set=0,binding=5,rg32f) uniform writeonly image2D coverage;
layout(set=0,binding=6,rg32f) uniform writeonly image2D candidate;
layout(set=1,binding=0,r32f) uniform readonly image2D rock;
layout(set=1,binding=1,r32f) uniform readonly image2D sand0;
layout(set=1,binding=2,r32f) uniform readonly image2D sand1;
layout(push_constant,std430) uniform Push { uint n,x,z,w,h,index,phase,reserved; } p;
void main(){ivec2 q=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(q,ivec2(p.n))))return;float s=p.index==0?imageLoad(sand0,q).x:imageLoad(sand1,q).x;float b=imageLoad(rock,q).x+s;imageStore(baseline,q,vec4(b));imageStore(coverage,q,vec4(0));imageStore(candidate,q,vec4(0));if(all(equal(q,ivec2(0))))marker[63]=0xbeefcafeu;}
