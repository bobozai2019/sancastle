#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Receipt {uint r[];};
struct InputCell {vec4 bed_water;vec4 flow;};
layout(set=0,binding=1,std430) readonly buffer Input {InputCell inputs[];};
layout(set=0,binding=2,std430) readonly buffer Candidate {vec4 values[];};
layout(set=1,binding=0,r32f) uniform writeonly image2D h0;
layout(set=1,binding=1,r32f) uniform writeonly image2D h1;
layout(set=1,binding=2,r32f) uniform writeonly image2D s0;
layout(set=1,binding=3,r32f) uniform writeonly image2D s1;
layout(set=1,binding=4,r32f) uniform writeonly image2D x0;
layout(set=1,binding=5,r32f) uniform writeonly image2D x1;
layout(set=1,binding=6,r32f) uniform writeonly image2D z0;
layout(set=1,binding=7,r32f) uniform writeonly image2D z1;
layout(set=1,binding=8,r32f) uniform readonly image2D bh0;
layout(set=1,binding=9,r32f) uniform readonly image2D bh1;
layout(set=1,binding=10,r32f) uniform readonly image2D bs0;
layout(set=1,binding=11,r32f) uniform readonly image2D bs1;
layout(set=1,binding=12,r32f) uniform readonly image2D bx0;
layout(set=1,binding=13,r32f) uniform readonly image2D bx1;
layout(set=1,binding=14,r32f) uniform readonly image2D bz0;
layout(set=1,binding=15,r32f) uniform readonly image2D bz1;
layout(push_constant,std430) uniform Push {uint n,index,phase,policy,pad0,pad1,pad2,pad3;}p;
void main(){uint i=gl_GlobalInvocationID.x;if(i>=p.n*p.n)return;ivec2 q=ivec2(i%p.n,i/p.n);
 if(p.phase==1u){imageStore(h0,q,imageLoad(bh0,q));imageStore(h1,q,imageLoad(bh1,q));imageStore(s0,q,imageLoad(bs0,q));imageStore(s1,q,imageLoad(bs1,q));imageStore(x0,q,imageLoad(bx0,q));imageStore(x1,q,imageLoad(bx1,q));imageStore(z0,q,imageLoad(bz0,q));imageStore(z1,q,imageLoad(bz1,q));return;}
 if(r[3]!=1u||p.policy==0u)return;
 vec4 old=vec4(inputs[i].bed_water.zw,inputs[i].flow.xy),next=values[i];
 if(old.x!=next.x){imageStore(h0,q,vec4(next.x));imageStore(h1,q,vec4(next.x));}
 if(old.y!=next.y){imageStore(s0,q,vec4(next.y));imageStore(s1,q,vec4(next.y));}
 if(old.z!=next.z){imageStore(x0,q,vec4(next.z));imageStore(x1,q,vec4(next.z));}
 if(old.w!=next.w){imageStore(z0,q,vec4(next.w));imageStore(z1,q,vec4(next.w));}
}
