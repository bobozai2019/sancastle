#[compute]
#version 450
layout(local_size_x=16,local_size_y=16) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=1,std430) readonly buffer Receipt {uint r[];};
layout(set=0,binding=2,std430) buffer Cells {uint v[];};
layout(set=0,binding=3,std430) readonly buffer Scratch {uint s[];};
layout(set=1,binding=0,rg32f) uniform image2D support0;
layout(set=1,binding=1,rg32f) uniform image2D support1;
layout(set=1,binding=2,r16f) uniform image2D compact0;
layout(set=1,binding=3,r16f) uniform image2D compact1;
layout(set=1,binding=4,rg32f) uniform image2D backup_support0;
layout(set=1,binding=5,rg32f) uniform image2D backup_support1;
layout(set=1,binding=6,r16f) uniform image2D backup_compact0;
layout(set=1,binding=7,r16f) uniform image2D backup_compact1;
layout(set=1,binding=8,rg32f) uniform image2D candidate_support;
layout(set=1,binding=9,r16f) uniform image2D candidate_compact;
layout(push_constant,std430) uniform Push {uint n,index,phase,reserved; float compact_target,pad0,pad1,pad2;}p;
bool finite_value(float a){return !isnan(a)&&!isinf(a);}
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(q,ivec2(p.n))))return;
 uint k=(uint(q.y)*p.n+uint(q.x))*16u;
 if(p.phase==2u){
  imageStore(support0,q,imageLoad(backup_support0,q));imageStore(support1,q,imageLoad(backup_support1,q));
  imageStore(compact0,q,imageLoad(backup_compact0,q));imageStore(compact1,q,imageLoad(backup_compact1,q));return;
 }
 if(p.phase==1u){
  if(r[3]==1u&&v[k]!=v[k+1u]){
   vec4 tag=imageLoad(candidate_support,q),compact=imageLoad(candidate_compact,q);
   imageStore(support0,q,tag);imageStore(support1,q,tag);
   if((c[3]==3u||c[23]==1u)&&uintBitsToFloat(v[k+1u])>uintBitsToFloat(v[k])){imageStore(compact0,q,compact);imageStore(compact1,q,compact);}
  }return;
 }
 vec4 a=imageLoad(support0,q),b=imageLoad(support1,q),ca=imageLoad(compact0,q),cb=imageLoad(compact1,q);
 imageStore(backup_support0,q,a);imageStore(backup_support1,q,b);
 imageStore(backup_compact0,q,ca);imageStore(backup_compact1,q,cb);
 vec2 old=p.index==0u?a.xy:b.xy;float compact=p.index==0u?ca.x:cb.x;
 float sand=uintBitsToFloat(v[k]),next=uintBitsToFloat(v[k+1u]),delta=next-sand;
 bool valid=finite_value(old.x)&&finite_value(old.y)&&old.x>=0.0&&old.x<=sand&&
   (old.x>0.0?old.y==sand:old.y==0.0)&&finite_value(compact)&&compact>=0.0&&compact<=1.0;
 if(!valid||c[23]>1u){v[k+15u]|=256u;imageStore(candidate_support,q,vec4(old,0,0));imageStore(candidate_compact,q,vec4(compact));return;}
 float tag=max(old.x-max(-delta,0.0),0.0);
 if(c[3]==3u&&delta>0.0){
  float moved=uintBitsToFloat(s[4096]),tagged=uintBitsToFloat(s[4097]),donor_compact=uintBitsToFloat(s[4098]);
  if(!finite_value(moved)||!finite_value(tagged)||!finite_value(donor_compact)||moved<=0.0||tagged<0.0||tagged>moved||donor_compact<0.0||donor_compact>1.0)v[k+15u]|=256u;
  else{tag+=delta*tagged/moved;compact=clamp((sand*compact+delta*donor_compact)/next,0.0,1.0);}
 }else if(c[23]==1u&&delta>0.0){tag+=delta;compact=max(compact,p.compact_target);}
 tag=clamp(tag,0.0,max(next,0.0));
 imageStore(candidate_support,q,vec4(tag,tag>0.0?next:0.0,0,0));
 imageStore(candidate_compact,q,vec4(compact));
}
