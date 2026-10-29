#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform readonly image2D h1;
layout(set=0,binding=1,r32f) uniform writeonly image2D h0;
layout(set=0,binding=2,rg32f) uniform readonly image2D momentum1;
layout(set=0,binding=3,rg32f) uniform writeonly image2D momentum0;


layout(set=0,binding=4,r32f) uniform readonly image2D s1;
layout(set=0,binding=5,r32f) uniform writeonly image2D s0;
layout(set=0,binding=6,r32f) uniform readonly image2D sand1;
layout(set=0,binding=7,r32f) uniform writeonly image2D sand0;
layout(set=0,binding=8,r16f) uniform readonly image2D wet1;
layout(set=0,binding=9,r16f) uniform writeonly image2D wet0;
layout(set=0,binding=10,r16f) uniform readonly image2D comp1;
layout(set=0,binding=11,r16f) uniform writeonly image2D comp0;
layout(set=0,binding=12,rgba32f) uniform readonly image2D flux1;
layout(set=0,binding=13,rgba32f) uniform writeonly image2D flux0;
layout(set=0,binding=14,std430) buffer Decision {uint d[];};
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);
 if(all(equal(q,ivec2(0))))d[5]=0u;
 imageStore(h0,q,imageLoad(h1,q));imageStore(momentum0,q,vec4(imageLoad(momentum1,q).rg,0.0,0.0));imageStore(s0,q,imageLoad(s1,q));
 imageStore(sand0,q,imageLoad(sand1,q));imageStore(wet0,q,imageLoad(wet1,q));imageStore(comp0,q,imageLoad(comp1,q));imageStore(flux0,q,imageLoad(flux1,q));
}
