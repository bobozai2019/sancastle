#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Control {uint control[];};
layout(set=0,binding=1,std430) buffer Stamp {uint stamp[];};
layout(set=0,binding=2,r32f) uniform readonly image2D sand;
layout(set=0,binding=3,r32f) uniform readonly image2D water;
layout(set=0,binding=4,r32f) uniform image2D visible_sand;
layout(set=0,binding=5,r32f) uniform writeonly image2D visible_water;
layout(set=0,binding=6,r32f) uniform image2D surface_wetness;
void main(){
 if(control[1]!=0u)return;
 uint i=gl_GlobalInvocationID.x;if(i>=65536u)return;
 ivec2 q=ivec2(i%256u,i/256u);
 float s=imageLoad(sand,q).r,h=imageLoad(water,q).r;
 float contact=smoothstep(0.001,0.003,max(h,0.0));
 float m=imageLoad(surface_wetness,q).r;
 if(abs(s-imageLoad(visible_sand,q).r)>0.005)m=0.4*contact;
 float dt=uintBitsToFloat(control[9]);
 m=clamp(m+(contact>0.0?dt*contact/0.75:-dt/30.0),0.0,1.0);
 if(s<=0.02)m=0.0;
 imageStore(surface_wetness,q,vec4(m));
 imageStore(visible_sand,q,vec4(s));imageStore(visible_water,q,vec4(h));
 if(i==0u){
  stamp[0]=control[2];stamp[1]=control[3];stamp[2]=control[4];stamp[3]=control[5];
  stamp[4]=control[10];stamp[5]=control[11];stamp[6]=control[6];stamp[7]=control[7];
 }
}
