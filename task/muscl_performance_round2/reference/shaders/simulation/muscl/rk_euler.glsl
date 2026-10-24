#[compute]
#version 450
#include "muscl_spatial.glslinc"
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
