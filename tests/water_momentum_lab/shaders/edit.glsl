#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(r32f,set=0,binding=0) uniform image2D bed;
layout(r32f,set=0,binding=1) uniform readonly image2D water;
layout(r32f,set=0,binding=2) uniform image2D qx;
layout(r32f,set=0,binding=3) uniform image2D qz;
layout(rgba32f,set=0,binding=4) uniform image2D coverage;
layout(rgba32f,set=0,binding=5) uniform writeonly image2D edit_stats;
layout(push_constant,std430) uniform Command {
 vec4 endpoints; // world xz start/end
 vec4 brush; // radius, signed depth, gain, response enum
 uvec4 ids; // size, reset coverage, operation, reserved
 vec4 origin; // fixed stroke origin, distinct from the current polyline segment
} c;
float weight(vec2 p,vec2 a,vec2 b,float r){
 vec2 s=b-a;float t=clamp(dot(p-a,s)/max(dot(s,s),1e-12),0.,1.);
 float d=length(p-a-t*s)/r;return d<1.?pow(1.-d*d,2.):0.;
}
void main(){
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(p,ivec2(c.ids.x))))return;
 vec2 point=(vec2(p)+.5-float(c.ids.x)*.5)*.125;
 vec2 a=c.endpoints.xy,b=c.endpoints.zw,s=b-a;
 vec2 near=a+clamp(dot(point-a,s)/max(dot(s,s),1e-12),0.,1.)*s;
 vec2 radial=point-c.origin.xy;vec2 dir=length(radial)>1e-8?normalize(radial):vec2(0);
 vec3 old=c.ids.y==1u?vec3(0):imageLoad(coverage,p).xyz;
 vec3 w=vec3(weight(point,a,b,c.brush.x),0,0);
 if(c.ids.z==2u){
  // Fixed world-X shoulders: translation preserves the discrete sum away from edges.
  vec2 off=vec2(2.*c.brush.x,0);
  w.y=weight(point,a+off,b+off,c.brush.x);
  w.z=weight(point,a-off,b-off,c.brush.x);
 }
 vec3 next=max(old,w),inc=next-old;
 float db=c.brush.y*(c.ids.z==2u?(.5*inc.y+.5*inc.z-inc.x):inc.x);
 float before=imageLoad(bed,p).r,after=max(0.,before+db);db=after-before;
 imageStore(coverage,p,vec4(next,0));imageStore(bed,p,vec4(after));
 float h=imageLoad(water,p).r;vec2 q=vec2(imageLoad(qx,p).r,imageLoad(qz,p).r),outq=q;
 float dv=c.brush.w<.5?0.:(c.brush.w<1.5?max(db,0.)*c.brush.z:db/.2*c.brush.z);
 if(h>.001&&db!=0.&&dv!=0.)outq+=h*dv*dir;
 float capped=0.;if(h>.001&&length(outq)>4.*h&&any(notEqual(outq,q))){outq*=4.*h/length(outq);capped=1.;}
 imageStore(qx,p,vec4(outq.x));imageStore(qz,p,vec4(outq.y));
 float energy=h>.001?(dot(outq,outq)-dot(q,q))/(2.*h):0.;
 imageStore(edit_stats,p,vec4(outq-q,energy,capped));
}
