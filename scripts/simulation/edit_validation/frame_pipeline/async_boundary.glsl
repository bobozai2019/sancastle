#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,r32f) uniform readonly image2D rock_state;
layout(set=0,binding=1,r32f) uniform readonly image2D sand_state;
layout(set=0,binding=2,r32f) uniform image2D water_state;
layout(set=0,binding=3,r32f) uniform image2D qx_state;
layout(set=0,binding=4,r32f) uniform image2D qz_state;
layout(set=0,binding=5,std430) buffer Control {uint control[];};
layout(set=0,binding=6,std430) readonly buffer Decision {uint d[];};
layout(set=0,binding=7,std430) readonly buffer Waves {vec4 waves[];};
layout(push_constant,std430) uniform Params {float area,mean_level,amplitude,omega;uint count,mode;float phase,period;}p;
shared float source[64],sink[64];
void main(){
 if(d[4]==2u||control[1]!=0u)return;
 uint lane=gl_LocalInvocationID.x;float time=uintBitsToFloat(control[8]),wave=0.0;
 for(uint j=0u;j<p.count;j++){
  vec4 a=waves[j];float u=(time-a.x)/a.y;
  if(u>=0.0&&u<1.0){float envelope=sin(3.141592653589793*u);wave+=a.z*envelope*envelope*(0.95+0.05*sin(6.283185307179586*u+a.w));}
 }
 wave=min(wave,0.25);float base=p.mean_level;
 if(p.mode==2u)base*=0.5+0.5*cos(6.283185307179586*time/p.period);
 float level=base+p.amplitude*sin(p.phase+time*p.omega)+wave;
 if(p.mode==3u){
  float phase=mod(time,p.period)/p.period;
  float envelope=smoothstep(0.05,0.20,phase)*(1.0-smoothstep(0.25,0.45,phase));
  level=p.mean_level+p.amplitude*envelope+wave;
 }
 float added=0.0,removed=0.0;
 for(uint z=lane;z<uint(imageSize(water_state).y);z+=64u){
  // The original-aspect scene has dry solid padding outside its 15m Z span.
  // Do not inject tide water into that padding. Other scene modes are unchanged.
  if(p.mode==3u&&(z<68u||z>=188u))continue;
  ivec2 q=ivec2(0,z);float old=imageLoad(water_state,q).r;
  float bed=imageLoad(rock_state,q).r+imageLoad(sand_state,q).r;
  float depth=max(0.0,level-bed),background=max(0.0,level-wave-bed);
  imageStore(water_state,q,vec4(depth));
  imageStore(qx_state,q,vec4(depth>0.0?wave*sqrt(9.81*max(background,0.01)):0.0));
  imageStore(qz_state,q,vec4(0.0));
  float delta=(depth-old)*p.area;added+=max(delta,0.0);removed+=max(-delta,0.0);
 }
 source[lane]=added;sink[lane]=removed;barrier();
 for(uint stride=32u;stride>0u;stride>>=1u){if(lane<stride){source[lane]+=source[lane+stride];sink[lane]+=sink[lane+stride];}barrier();}
 if(lane==0u){control[22]=floatBitsToUint(uintBitsToFloat(control[22])+source[0]);control[23]=floatBitsToUint(uintBitsToFloat(control[23])+sink[0]);control[24]=floatBitsToUint(level);control[25]=floatBitsToUint(wave);}
}
