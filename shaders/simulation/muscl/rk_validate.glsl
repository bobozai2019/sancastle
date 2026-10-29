#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform readonly image2D h;
layout(set=0,binding=1,rg32f) uniform readonly image2D momentum;

layout(set=0,binding=2,r32f) uniform readonly image2D s;
layout(set=0,binding=3,r32f) uniform readonly image2D sand;
layout(set=0,binding=4,r16f) uniform readonly image2D wet;
layout(set=0,binding=5,r16f) uniform readonly image2D comp;
layout(set=0,binding=6,std430) buffer Trial {uint tr[];};
layout(set=0,binding=7,std430) buffer Control {uint control[];};
#include "muscl_math.glslinc"
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);
 vec4 a=vec4(imageLoad(h,q).r,imageLoad(momentum,q).rg,imageLoad(s,q).r);
 vec3 b=vec3(imageLoad(sand,q).r,imageLoad(wet,q).r,imageLoad(comp,q).r);
 uint flags=0u;
 if(!finite4(a)||any(isnan(b))||any(isinf(b)))flags|=1u;
 if(min(a.x,a.w)<0.0||any(lessThan(b,vec3(0.0))))flags|=2u;
 if(b.y>1.0||b.z>1.0)flags|=16u;
 if(flags!=0u){atomicOr(tr[14],flags);atomicOr(control[1],16u);}
}
