#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform readonly image2D water_state;
layout(set=0,binding=1,r32f) uniform readonly image2D momentum_x_state;
layout(set=0,binding=2,r32f) uniform readonly image2D momentum_z_state;
layout(set=0,binding=3,r32f) uniform writeonly image2D tile_max_out;
shared float speeds[64];
bool finite_value(float x) {return !isnan(x)&&!isinf(x);}
void main(){
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);uint lane=gl_LocalInvocationID.y*8u+gl_LocalInvocationID.x;
 float h=imageLoad(water_state,p).r,qx=imageLoad(momentum_x_state,p).r,qz=imageLoad(momentum_z_state,p).r;
 float speed=h>0.001?max(abs(qx),abs(qz))/max(h,0.005)+sqrt(9.81*h):0.01;
 bool valid=finite_value(h)&&finite_value(qx)&&finite_value(qz)&&finite_value(speed)&&h>=0.0;
 speeds[lane]=valid?speed:-1.0;barrier();
 for(uint stride=32u;stride>0u;stride>>=1u){
  if(lane<stride)speeds[lane]=(speeds[lane]<0.0||speeds[lane+stride]<0.0)?-1.0:max(speeds[lane],speeds[lane+stride]);
  barrier();
 }
 if(lane==0u)imageStore(tile_max_out,ivec2(gl_WorkGroupID.xy),vec4(speeds[0]));
}
