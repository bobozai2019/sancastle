#[compute]
#version 450
layout(local_size_x=16,local_size_y=16) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=2,std430) writeonly buffer Cells {uint v[];};
layout(set=0,binding=3,std430) buffer Scratch {uint s[];};
layout(set=0,binding=4,r32f) uniform readonly image2D baseline;
layout(set=0,binding=5,rg32f) uniform readonly image2D coverage;
layout(set=0,binding=6,rg32f) uniform writeonly image2D candidate;
layout(set=0,binding=7,rgba32f) uniform readonly image2D castle_template;
layout(set=1,binding=0,r32f) uniform readonly image2D rock;
layout(set=1,binding=1,r32f) uniform readonly image2D sand0;
layout(set=1,binding=2,r32f) uniform readonly image2D sand1;
layout(set=1,binding=3,r32f) uniform readonly image2D water0;
layout(set=1,binding=4,r32f) uniform readonly image2D water1;
layout(set=1,binding=15,r8) uniform readonly image2D obstacle;
layout(push_constant,std430) uniform Push { uint n,x,z,w,h,index,phase,reserved; } p;
float f(uint i){return uintBitsToFloat(c[i]);}
vec3 sample_castle(ivec2 q){
 vec2 world=(vec2(q)+0.5-vec2(float(p.n)*0.5))*f(40)-vec2(f(24),f(25));
 float co=cos(f(28)),si=sin(f(28));
 vec2 local=vec2(co*world.x+si*world.y,-si*world.x+co*world.y)/f(29);
 if(any(lessThan(local,vec2(-2)))||any(greaterThan(local,vec2(2))))return vec3(0);
 vec2 uv=(local+2.0)/f(45);ivec2 lo=ivec2(floor(uv)),hi=min(lo+1,ivec2(64));vec2 t=fract(uv);
 float h=mix(mix(imageLoad(castle_template,lo).x,imageLoad(castle_template,ivec2(hi.x,lo.y)).x,t.x),mix(imageLoad(castle_template,ivec2(lo.x,hi.y)).x,imageLoad(castle_template,hi).x,t.x),t.y);
 vec4 mask=imageLoad(castle_template,ivec2(floor(uv+0.5)));
 return vec3(h*f(31),mask.yz);
}
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(q,ivec2(p.n))))return;
 if(p.phase==1u){
  if(any(notEqual(q,ivec2(0))))return;
  float high=-3.402823466e38,low=3.402823466e38;uint flags=0u,count=0u;
  for(uint z=0u;z<p.n;z++)for(uint x=0u;x<p.n;x++){
   ivec2 cell=ivec2(x,z);if(sample_castle(cell).y<0.5)continue;
   float bed=imageLoad(rock,cell).x+(p.index==0u?imageLoad(sand0,cell).x:imageLoad(sand1,cell).x);
   if(isnan(bed)||isinf(bed))flags|=256u;
   high=max(high,bed);low=min(low,bed);count++;
  }
  // Castle targets use the fixed world datum, independent of existing piles.
  if(count==0u)flags|=4096u;
  s[0]=floatBitsToUint(0.0);s[1]=floatBitsToUint(low);s[2]=flags;return;
 }
 uint k=(uint(q.y)*p.n+uint(q.x))*16u;for(uint j=0;j<16u;j++)v[k+j]=0;
 float old=p.index==0?imageLoad(sand0,q).x:imageLoad(sand1,q).x;
 float r=imageLoad(rock,q).x,water=p.index==0?imageLoad(water0,q).x:imageLoad(water1,q).x;
 float b=imageLoad(baseline,q).x;vec2 cv=imageLoad(coverage,q).xy;
 float next=old,target=old+r,weight=0.0;vec2 outward=vec2(0);uint flags=0;
 vec2 a=vec2(f(24),f(25)),end=vec2(f(26),f(27)),ab=end-a;
 bool moving=dot(ab,ab)>1e-12;
 if(c[3]==2u&&moving){
  vec2 world=(vec2(q)+0.5-vec2(float(p.n)*0.5))*f(40);
  vec2 near=a+ab*clamp(dot(world-a,ab)/dot(ab,ab),0.0,1.0);
  float d=length(world-near),inner=f(33)*0.5,outer=f(32)*0.5;
  outward=d>0.0?(world-near)/d:vec2(0);
  float profile=d<=inner?1.0:(d<outer?(outer-d)/max(outer-inner,1e-8):0.0);
  bool hit=profile>0.0;
  if(hit||cv.y>0.0){target=hit?b+f(31)*profile:cv.x;if(cv.y>0.0)target=max(target,cv.x);next=max(old,target-r);flags|=1u;cv=vec2(target,1.0);}
 }else if(c[3]==1u){
  vec3 stamp=sample_castle(q);flags|=s[2];
  if(stamp.y>=0.5&&imageLoad(obstacle,q).x<=0.0){target=stamp.x;next=max(old,target-r);flags|=1u;cv=vec2(target,1.0);}
  vec2 downhill=vec2(sample_castle(q-ivec2(1,0)).x-sample_castle(q+ivec2(1,0)).x,sample_castle(q-ivec2(0,1)).x-sample_castle(q+ivec2(0,1)).x);
  outward=length(downhill)>0.0?normalize(downhill):vec2(0);
 }else if(c[3]==3u&&moving){
  vec2 world=(vec2(q)+0.5-vec2(float(p.n)*0.5))*f(40);
  bool reverse=a.x>end.x||(a.x==end.x&&a.y>end.y);
  vec2 ga=reverse?end:a,gb=reverse?a:end,gab=gb-ga;
  vec2 near=ga+gab*clamp(dot(world-ga,gab)/dot(gab,gab),0.0,1.0),delta=world-near;
  float d=length(delta),radius=f(34)*0.5,shoulder=f(36);
  outward=d>0.0?delta/d:vec2(0);
  // Classify against the original directed line. Explicit precise products
  // preserve the zero-side tie; a contracted normalized dot can put diagonal
  // cap cells on different sides despite their exact collinearity.
  precise float cross_x=(world.x-a.x)*ab.y;
  precise float cross_z=(world.y-a.y)*ab.x;
  precise float signed_side=cross_z-cross_x;
  if(d<radius){
   float profile=max(0.0,1.0-d*d/(radius*radius));
   target=max(r,b-f(35)*profile);
   if(cv.y>0.0)target=max(r,profile<=cv.y?cv.x:min(target,cv.x));
   next=min(old,max(0.0,target-r));flags|=3u;cv=vec2(target,max(profile,cv.y));
  }else if(d<radius+shoulder&&cv.y==0.0&&imageLoad(obstacle,q).x==0.0){
   target=b+f(37);weight=sin(3.141592653589793*(d-radius)/shoulder);
   if(weight>0.0)flags|=signed_side>=0.0?5u:9u;
  }
 }else if(c[3]!=2u&&c[3]!=3u){flags|=2048u;}
 if(isnan(old)||isinf(old)||old<0.0||isnan(next)||isinf(next)||isnan(r)||isinf(r))flags|=256u;
 if(next!=old&&water>0.0&&p.phase!=2u)flags|=512u;
 if((flags&1u)!=0u&&imageLoad(obstacle,q).x>0.0)flags|=1024u;
 v[k]=floatBitsToUint(old);v[k+1]=floatBitsToUint(next);v[k+2]=floatBitsToUint(r);v[k+3]=floatBitsToUint(water);
 v[k+10]=floatBitsToUint(b);v[k+11]=floatBitsToUint(target);v[k+15]=flags;
 v[k+12]=floatBitsToUint(weight);v[k+13]=floatBitsToUint(outward.x);v[k+14]=floatBitsToUint(outward.y);
 imageStore(candidate,q,vec4(cv,0,0));
}
