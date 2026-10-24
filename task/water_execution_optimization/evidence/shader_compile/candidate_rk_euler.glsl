
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform readonly image2D rock_state;
layout(set=0,binding=1,r32f) uniform readonly image2D sand_state;
layout(set=0,binding=2,r32f) uniform readonly image2D water_state;
layout(set=0,binding=3,r32f) uniform readonly image2D qx_state;
layout(set=0,binding=4,r32f) uniform readonly image2D qz_state;
layout(set=0,binding=5,r32f) uniform readonly image2D sediment_state;
layout(set=0,binding=6,r8) uniform readonly image2D obstacle;
layout(set=0,binding=7,rgba32f) uniform readonly image2D stage_in;
layout(set=0,binding=8,rgba32f) uniform writeonly image2D stage_out;
layout(set=0,binding=9,rgba32f) uniform image2D edge_x;
layout(set=0,binding=10,rgba32f) uniform image2D edge_z;
layout(set=0,binding=11,rgba32f) uniform image2D correction;
layout(set=0,binding=12,rg32f) uniform image2D bed_source;
layout(set=0,binding=13,r32f) uniform image2D drain;
layout(set=0,binding=14,rg32f) uniform image2D speed_tiles;
layout(set=0,binding=15,std430) buffer Decision {uint d[];};
layout(set=0,binding=16,std430) buffer Trial {uint tr[];};
layout(set=0,binding=17,std430) buffer Safety {uint stats[];};
layout(push_constant,std430) uniform Params {uint phase,boundary_enabled;float wave_retention;uint reserved1;}p;
const float G=9.81;
const float DRY=0.001;
const float VELOCITY_DEPTH=0.005;
const float EPS=1.1920928955078125e-7;
bool finite1(float x){return !isnan(x)&&!isinf(x);}
bool finite4(vec4 x){return !any(isnan(x))&&!any(isinf(x));}
float mc(float l,float r){return l*r>0.0?sign(l)*min(min(2.0*abs(l),2.0*abs(r)),0.5*abs(l+r)):0.0;}
vec4 mc4(vec4 l,vec4 r){return vec4(mc(l.x,r.x),mc(l.y,r.y),mc(l.z,r.z),mc(l.w,r.w));}
// Convex blend of MC and Superbee slopes. Never reduce the Rusanov speed
// bound, add energy, or change the wet/dry and positivity safeguards.
float retained_slope(float l,float r,float retention){
 float base=mc(l,r);
 if(retention<=0.0||l*r<=0.0)return base;
 float sharp=sign(l)*max(min(2.0*abs(l),abs(r)),min(abs(l),2.0*abs(r)));
 return mix(base,sharp,retention);
}
vec4 retained_slopes(vec4 l,vec4 r,float retention){return vec4(retained_slope(l.x,r.x,retention),retained_slope(l.y,r.y,retention),retained_slope(l.z,r.z,retention),retained_slope(l.w,r.w,retention));}
vec4 cap_state(vec4 a,out bool limited){
 limited=false;
 if(a.x<=DRY){a.yz=vec2(0.0);return a;}
 float length_q=length(a.yz),cap=a.x*max(1.5,3.0*sqrt(G*a.x));
 if(length_q>cap){a.yz*=cap/length_q;limited=true;}
 return a;
}

// stats[] and tr[] must be bound before including this file.
void add_float(uint at,float value){
 if(value==0.0)return;
 uint old=stats[at],seen;
 do{seen=old;old=atomicCompSwap(stats[at],seen,floatBitsToUint(uintBitsToFloat(seen)+value));}while(old!=seen);
}
void add_counter(uint at,uint amount){
 if(amount==0u)return;
 uint old=atomicAdd(stats[at],amount);
 if(old>0xffffffffu-amount)atomicAdd(stats[at+1u],1u);
}
float nonnegative(float value,float magnitude,uint base,uint count_offset,uint volume_offset,float area){
 if(!finite1(value)){atomicOr(tr[14],1u);return 0.0;}
 if(value<0.0){
  float bound=min(2e-6,8.0*EPS*magnitude);
  if(-value>bound){atomicOr(tr[14],2u);return 0.0;}
  add_counter(base+count_offset,1u);add_float(base+volume_offset,-value*area);return 0.0;
 }
 return value;
}

ivec2 extent(){return imageSize(water_state);}
bool inside(ivec2 q){return all(greaterThanEqual(q,ivec2(0)))&&all(lessThan(q,extent()));}
bool blocked(ivec2 q){return imageLoad(obstacle,q).r>=0.5;}
vec4 state_at(ivec2 q){
 vec4 a=p.phase==0u?vec4(imageLoad(water_state,q).r,imageLoad(qx_state,q).r,imageLoad(qz_state,q).r,imageLoad(sediment_state,q).r):imageLoad(stage_in,q);
 if(!finite4(a)){atomicOr(tr[14],1u);return vec4(0.0);}
 if(a.x<0.0||a.w<0.0)atomicOr(tr[14],2u);
 return a;
}
vec4 primitive(ivec2 q){
 vec4 a=state_at(q);float bed=imageLoad(rock_state,q).r+imageLoad(sand_state,q).r;
 if(!finite1(bed)){atomicOr(tr[14],1u);bed=0.0;}
 vec2 uv=a.x>DRY?a.yz/max(a.x,VELOCITY_DEPTH):vec2(0.0);
 return vec4(max(a.x,0.0),bed+max(a.x,0.0),uv);
}
bool reconstructable(ivec2 q){
 if(q.x==0||q.y==0||q.x==extent().x-1||q.y==extent().y-1||blocked(q)||state_at(q).x<=DRY)return false;
 for(int k=0;k<4;k++){
  ivec2 v=k==0?ivec2(-1,0):k==1?ivec2(1,0):k==2?ivec2(0,-1):ivec2(0,1);
  if(blocked(q+v)||state_at(q+v).x<=DRY)return false;
 }
 return true;
}
vec4 face_slope(ivec2 q,ivec2 axis,vec4 c){
 vec4 slope=retained_slopes(c-primitive(q-axis),primitive(q+axis)-c,p.wave_retention);
 slope.x*=min(1.0,2.0*c.x/max(abs(slope.x),1.17549435e-38));
 return slope;
}
vec4 face(ivec2 q,ivec2 axis,float side){
 vec4 c=primitive(q);
 if(!reconstructable(q))return c;
 return c+0.5*side*face_slope(q,axis,c);
}
// A cell's state is immutable during this pass. Reuse its reconstruction for
// both shared edges and the bed source without changing face arithmetic.
void cell_faces(ivec2 q,out vec4 xm,out vec4 xp,out vec4 zm,out vec4 zp){
 vec4 c=primitive(q);
 if(!reconstructable(q)){xm=c;xp=c;zm=c;zp=c;return;}
 vec4 xs=face_slope(q,ivec2(1,0),c),zs=face_slope(q,ivec2(0,1),c);
 xm=c+0.5*(-1.0)*xs;xp=c+0.5*xs;
 zm=c+0.5*(-1.0)*zs;zp=c+0.5*zs;
}
vec4 evaluate_edge(ivec2 q,ivec2 axis,vec4 l,out vec2 corrections){
 ivec2 other=q+axis;
 vec4 r=inside(other)?face(other,axis,-1.0):l;
 float zmax=max(l.y-l.x,r.y-r.x),hl=max(0.0,l.y-zmax),hr=max(0.0,r.y-zmax);
 float ul=axis.x==1?l.z:l.w,ur=axis.x==1?r.z:r.w;
 float a=max(abs(ul)+sqrt(G*hl),abs(ur)+sqrt(G*hr));
 bool wall=!inside(other)||blocked(q)||(inside(other)&&blocked(other));
 if(wall){corrections=0.5*G*vec2(l.x*l.x,r.x*r.x);return vec4(0.0,0.0,0.0,a);}
 vec3 ql=vec3(hl,hl*l.zw),qr=vec3(hr,hr*r.zw);
 vec3 fl=ql*ul,fr=qr*ur;int normal=axis.x==1?1:2;
 fl[normal]+=0.5*G*hl*hl;fr[normal]+=0.5*G*hr*hr;
 corrections=0.5*G*vec2(l.x*l.x-hl*hl,r.x*r.x-hr*hr);
 return vec4(0.5*(fl+fr)-0.5*a*(qr-ql),a);
}

vec4 transfer(vec3 raw,ivec2 first,ivec2 second){
 ivec2 donor=raw.x>=0.0?first:second;
 vec3 f=raw*imageLoad(drain,donor).r;
 vec4 a=state_at(donor);float c=a.x>0.0?a.w/a.x:0.0;
 return vec4(f,f.x*c);
}
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);vec4 old=state_at(q);
 if(blocked(q)){imageStore(stage_out,q,vec4(old.x,0.0,0.0,old.w));return;}
 vec4 left=vec4(0.0),right=vec4(0.0),top=vec4(0.0),bottom=vec4(0.0);
 vec4 corr=imageLoad(correction,q);
 float pl,pr=corr.x,pt,pb=corr.z;
 if(q.x>0){left=transfer(imageLoad(edge_x,q-ivec2(1,0)).xyz,q-ivec2(1,0),q);pl=imageLoad(correction,q-ivec2(1,0)).y;}
 else {float h=face(q,ivec2(1,0),-1.0).x;pl=0.5*G*h*h;}
 if(q.x+1<extent().x)right=transfer(imageLoad(edge_x,q).xyz,q,q+ivec2(1,0));
 if(q.y>0){top=transfer(imageLoad(edge_z,q-ivec2(0,1)).xyz,q-ivec2(0,1),q);pt=imageLoad(correction,q-ivec2(0,1)).w;}
 else {float h=face(q,ivec2(0,1),-1.0).x;pt=0.5*G*h*h;}
 if(q.y+1<extent().y)bottom=transfer(imageLoad(edge_z,q).xyz,q,q+ivec2(0,1));
 float dt=uintBitsToFloat(tr[3]),dx=uintBitsToFloat(tr[11]),ratio=dt/dx;
 vec4 result=old+ratio*(left-right+top-bottom);
 result.yz+=ratio*vec2(pl-pr,pt-pb)+dt*imageLoad(bed_source,q).xy;
 vec4 magnitude=abs(old)+ratio*(abs(left)+abs(right)+abs(top)+abs(bottom));
 uint base=16u+p.phase*8u;
 if(!finite4(result)){atomicOr(tr[14],1u);result=vec4(0.0);}
 result.x=nonnegative(result.x,magnitude.x,base,0u,6u,dx*dx);
 result.w=nonnegative(result.w,magnitude.w,base,2u,7u,dx*dx);
 bool limited;result=cap_state(result,limited);
 if(limited)add_counter(base+4u,1u);
 if(p.boundary_enabled!=0u&&q.x==0)result.yz=vec2(0.0);
 imageStore(stage_out,q,result);
 if(all(equal(q,ivec2(0))))tr[15]=3u+p.phase*4u;
}
