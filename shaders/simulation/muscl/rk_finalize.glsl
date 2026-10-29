#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform readonly image2D h0;
layout(set=0,binding=1,rg32f) uniform readonly image2D momentum0;

layout(set=0,binding=2,r32f) uniform readonly image2D s0;
layout(set=0,binding=3,rgba32f) uniform readonly image2D u2;
layout(set=0,binding=4,r32f) uniform readonly image2D sand0;
layout(set=0,binding=5,r16f) uniform readonly image2D wet0;
layout(set=0,binding=6,r16f) uniform readonly image2D comp0;
layout(set=0,binding=7,r8) uniform readonly image2D obstacle;
layout(set=0,binding=8,rgba32f) uniform readonly image2D ex0;
layout(set=0,binding=9,rgba32f) uniform readonly image2D ez0;
layout(set=0,binding=10,rgba32f) uniform readonly image2D ex1;
layout(set=0,binding=11,rgba32f) uniform readonly image2D ez1;
layout(set=0,binding=12,r32f) uniform readonly image2D drain0;
layout(set=0,binding=13,r32f) uniform readonly image2D drain1;
layout(set=0,binding=14,r32f) uniform writeonly image2D h1;
layout(set=0,binding=15,rg32f) uniform writeonly image2D momentum1;

layout(set=0,binding=16,r32f) uniform writeonly image2D s1;
layout(set=0,binding=17,r32f) uniform writeonly image2D sand1;
layout(set=0,binding=18,r16f) uniform writeonly image2D wet1;
layout(set=0,binding=19,r16f) uniform writeonly image2D comp1;
layout(set=0,binding=20,rgba32f) uniform writeonly image2D flux1;
layout(set=0,binding=21,std430) buffer Decision {uint d[];};
layout(set=0,binding=22,std430) buffer Trial {uint tr[];};
layout(set=0,binding=23,std430) buffer Safety {uint stats[];};
#include "muscl_math.glslinc"
#include "muscl_stats.glslinc"
float net(ivec2 first,ivec2 second,bool along_x){
 float a=along_x?imageLoad(ex0,first).x:imageLoad(ez0,first).x;
 float b=along_x?imageLoad(ex1,first).x:imageLoad(ez1,first).x;
 return 0.5*(a*imageLoad(drain0,a>=0.0?first:second).r+b*imageLoad(drain1,b>=0.0?first:second).r);
}
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy),size=imageSize(h0);
 vec4 old=vec4(imageLoad(h0,q).r,imageLoad(momentum0,q).rg,imageLoad(s0,q).r);
 vec4 value=0.5*old+0.5*imageLoad(u2,q);bool limited;value=cap_state(value,limited);
 if(!finite4(value)){atomicOr(tr[14],1u);return;}
 if(value.x<0.0||value.w<0.0){atomicOr(tr[14],2u);return;}
 if(imageLoad(obstacle,q).r>=0.5||(tr[12]!=0u&&q.x==0))value.yz=vec2(0.0);
 if(limited)atomicAdd(tr[16],1u);
 imageStore(h1,q,vec4(value.x));imageStore(momentum1,q,vec4(value.y,value.z,0.0,0.0));imageStore(s1,q,vec4(value.w));
 imageStore(sand1,q,imageLoad(sand0,q));imageStore(wet1,q,imageLoad(wet0,q));imageStore(comp1,q,imageLoad(comp0,q));
 float left=q.x>0?net(q-ivec2(1,0),q,true):0.0;
 float right=q.x+1<size.x?net(q,q+ivec2(1,0),true):0.0;
 float top=q.y>0?net(q-ivec2(0,1),q,false):0.0;
 float bottom=q.y+1<size.y?net(q,q+ivec2(0,1),false):0.0;
 imageStore(flux1,q,vec4(max(-left,0.0),max(right,0.0),max(-top,0.0),max(bottom,0.0))*uintBitsToFloat(tr[11]));
 if(all(equal(q,ivec2(0)))){
  tr[15]=8u;
 }
}
