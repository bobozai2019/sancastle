#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,rg32f) uniform image2D support0;
layout(set=0,binding=1,rg32f) uniform image2D support1;
layout(set=0,binding=2,r32f) uniform readonly image2D sand0;
layout(set=0,binding=3,r32f) uniform readonly image2D sand1;
layout(set=0,binding=4,std430) readonly buffer Result {vec2 result[];};
layout(set=0,binding=5,std430) buffer Active {uint has_tagged_sand;};
layout(set=0,binding=6,std430) writeonly buffer Dispatch {uint groups[];};
layout(push_constant,std430) uniform Push {uint n,index,phase,pad;} p;
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);
 if(p.phase==2u){if(all(equal(q,ivec2(0))))has_tagged_sand=0u;return;}
 if(p.phase==3u){if(all(equal(q,ivec2(0)))){groups[0]=has_tagged_sand==0u?p.n/8u:0u;groups[1]=p.n/8u;groups[2]=1u;groups[3]=has_tagged_sand!=0u?p.n/8u:0u;groups[4]=p.n/8u;groups[5]=1u;}return;}
 if(any(greaterThanEqual(q,ivec2(p.n))))return;
 if(p.phase==0u){
  vec2 old=p.index==0u?imageLoad(support0,q).xy:imageLoad(support1,q).xy;
  float sand=p.index==0u?imageLoad(sand0,q).x:imageLoad(sand1,q).x;
  float tag=clamp(old.x-max(old.y-sand,0.0),0.0,sand);
  if(tag>0.0)atomicOr(has_tagged_sand,1u);
  vec4 value=vec4(tag,tag>0.0?sand:0.0,0,0);
  if(p.index==0u)imageStore(support1,q,value);else imageStore(support0,q,value);
 }else{
  float sand=p.index==0u?imageLoad(sand0,q).x:imageLoad(sand1,q).x;
  vec2 value=has_tagged_sand==0u?vec2(0):result[uint(q.y)*p.n+uint(q.x)];
  imageStore(support0,q,vec4(value,0,0));imageStore(support1,q,vec4(value,0,0));
 }
}

