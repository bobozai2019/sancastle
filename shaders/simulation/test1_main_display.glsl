#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba32f,set=0,binding=0) uniform readonly image2D capture_state;
layout(r32f,set=0,binding=1) uniform writeonly image2D rock;
layout(r32f,set=0,binding=2) uniform writeonly image2D sand;
layout(r32f,set=0,binding=3) uniform writeonly image2D water;
layout(r32f,set=0,binding=4) uniform writeonly image2D qx;
layout(r32f,set=0,binding=5) uniform writeonly image2D qz;
layout(r32f,set=0,binding=6) uniform image2D wetness;
layout(r32f,set=0,binding=7) uniform writeonly image2D compaction;
layout(push_constant,std430) uniform Params {float dt;float reset;float pad0;float pad1;} params;
vec4 state_at(ivec2 p) {return imageLoad(capture_state,clamp(p,ivec2(0),ivec2(511,255)));}
void main() {
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);
 vec2 world=(vec2(p)+0.5)*0.125-16.0;
 // Main's +Z row direction; test1 Unity +Z is Godot -Z.
 vec2 uv=vec2((world.x+15.0)/30.0,(7.5-world.y)/15.0);
 vec2 cell=uv*vec2(512,256)-0.5;
 ivec2 low=ivec2(floor(cell));vec2 f=fract(cell);
 vec4 a=state_at(low),b=state_at(low+ivec2(1,0));
 vec4 c=state_at(low+ivec2(0,1)),d=state_at(low+ivec2(1,1));
 vec4 weights=vec4((1-f.x)*(1-f.y),f.x*(1-f.y),(1-f.x)*f.y,f.x*f.y);
 float bed=dot(vec4(a.w,b.w,c.w,d.w),weights);
 vec4 depths=max(vec4(a.z,b.z,c.z,d.z)-0.05,vec4(0));
 float h=dot(depths,weights);
 // Convert each cell's velocity*depth BEFORE interpolation, not v(mean)*h(mean).
 float mx=dot(vec4(a.x,b.x,c.x,d.x)*depths,weights);
 float mz=-dot(vec4(a.y,b.y,c.y,d.y)*depths,weights);
 if(any(lessThan(uv,vec2(0)))||any(greaterThan(uv,vec2(1)))) {h=0.0;mx=0.0;mz=0.0;}
 float old_wet=params.reset>0.5?0.15:imageLoad(wetness,p).r;
 // Presentation-only damp-sand trace; no mutation of captured or main authority.
 float moist=max(mix(0.15,old_wet,exp(-params.dt/20.0)),smoothstep(0.0,0.025,h));
 imageStore(rock,p,vec4(0));imageStore(sand,p,vec4(bed));
 imageStore(water,p,vec4(h));imageStore(qx,p,vec4(mx));imageStore(qz,p,vec4(mz));
 imageStore(wetness,p,vec4(moist));imageStore(compaction,p,vec4(0.0));
}
