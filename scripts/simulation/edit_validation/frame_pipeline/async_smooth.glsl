#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=1,std430) buffer Receipt {uint r[];};
layout(set=0,binding=2,std430) buffer Cells {uint v[];};
layout(set=0,binding=3,std430) readonly buffer Control {uint control[];};
layout(set=1,binding=0,r32f) uniform image2D sand0;
layout(set=1,binding=1,r32f) uniform image2D sand1;
layout(set=1,binding=2,r16f) uniform image2D compact0;
layout(set=1,binding=3,r16f) uniform image2D compact1;
layout(set=1,binding=4,rg32f) uniform image2D support0;
layout(set=1,binding=5,rg32f) uniform image2D support1;
layout(push_constant,std430) uniform Params {uint mode,phase,pad0,pad1;}p;
float f(uint i){return uintBitsToFloat(c[i]);}
bool finite_value(float a){return !isnan(a)&&!isinf(a);}
void add(float x,inout float s,inout float e){precise float y=x-e;precise float t=s+y;e=(t-s)-y;s=t;}
float weight(ivec2 q){
 vec2 a=vec2(f(24),f(25)),b=vec2(f(26),f(27)),d=b-a;
 vec2 position=(vec2(q)+0.5)*0.125-16.0,closest=a;
 if(dot(d,d)>1e-6)closest+=d*clamp(dot(position-a,d)/dot(d,d),0.0,1.0);
 float distance=length(position-closest);
 return distance<=f(28)?max(0.001,1.0-distance/f(28)):0.0;
}
void main(){
 if(control[1]!=0u||r[3]!=1u)return;
 ivec2 lo=ivec2(c[32],c[33]),hi=ivec2(c[34],c[35]);
 if(p.phase==1u){
  ivec2 q=ivec2(gl_GlobalInvocationID.xy)+lo;if(any(greaterThan(q,hi)))return;
  uint k=(uint(q.y)*256u+uint(q.x))*16u;if(v[k+15u]!=1u)return;
  float next=uintBitsToFloat(v[k+1u]);
  if(p.mode==4u){imageStore(compact0,q,vec4(next));imageStore(compact1,q,vec4(next));}
  else{
   imageStore(sand0,q,vec4(next));imageStore(sand1,q,vec4(next));
   vec2 old=imageLoad(support0,q).xy;float tag=clamp(old.x-max(old.y-next,0.0),0.0,next);
   vec4 value=vec4(tag,tag>0.0?next:0.0,0,0);imageStore(support0,q,value);imageStore(support1,q,value);
  }return;
 }
 float before=0.0,target=0.0,weights=0.0,e0=0.0,e1=0.0,e2=0.0;uint count=0u;
 for(int z=lo.y;z<=hi.y;z++)for(int x=lo.x;x<=hi.x;x++){
  ivec2 q=ivec2(x,z);uint k=(uint(z)*256u+uint(x))*16u;v[k+15u]=0u;float w=weight(q);if(w<=0.0)continue;
  float old=p.mode==4u?imageLoad(compact0,q).x:imageLoad(sand0,q).x;
  vec2 tag=imageLoad(support0,q).xy;
  float sand=imageLoad(sand0,q).x;
  if(!finite_value(old)||old<0.0||(p.mode==4u&&old>1.0)||!finite_value(sand)||sand<0.0||!finite_value(tag.x)||!finite_value(tag.y)||tag.x<0.0||tag.x>sand||(tag.x>0.0?tag.y!=sand:tag.y!=0.0)){r[3]=3u;r[20]=16u;return;}
  v[k]=floatBitsToUint(old);v[k+2u]=floatBitsToUint(w);v[k+15u]=1u;count++;
  add(old,before,e0);add(old*w,target,e1);add(w,weights,e2);
 }
 if(count==0u||weights<=1e-7){r[3]=3u;r[20]=8u;return;}
 target/=weights;float after=0.0,e3=0.0;
 for(int z=lo.y;z<=hi.y;z++)for(int x=lo.x;x<=hi.x;x++){
  uint k=(uint(z)*256u+uint(x))*16u;if(v[k+15u]!=1u)continue;
  float old=uintBitsToFloat(v[k]),w=uintBitsToFloat(v[k+2u]);
  float next=p.mode==4u?clamp(old+0.2*f(29)*w,0.0,1.0):mix(old,target,f(29)*w);
  v[k+1u]=floatBitsToUint(next);add(next,after,e3);
 }
 float correction=(before-after)/float(count),total=0.0,e4=0.0;
 for(int z=lo.y;z<=hi.y;z++)for(int x=lo.x;x<=hi.x;x++){
  uint k=(uint(z)*256u+uint(x))*16u;if(v[k+15u]!=1u)continue;
  float next=uintBitsToFloat(v[k+1u]);if(p.mode==3u)next=max(0.0,next+correction);
  if(!finite_value(next)){r[3]=3u;r[20]=16u;return;}v[k+1u]=floatBitsToUint(next);add(next,total,e4);
 }
 if(p.mode==3u&&abs(total-before)>max(1e-5,2e-6*abs(before))){r[3]=3u;r[20]=16u;return;}
 r[14]=r[12]+1u;r[15]=r[13]+uint(r[14]==0u);r[22]=count;
 r[24]=uint(lo.x);r[25]=uint(lo.y);r[26]=uint(hi.x-lo.x+1);r[27]=uint(hi.y-lo.y+1);
}
