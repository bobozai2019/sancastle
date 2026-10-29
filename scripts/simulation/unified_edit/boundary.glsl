#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,r32f) uniform readonly image2D rock_state;
layout(set=0,binding=1,r32f) uniform readonly image2D sand_state;
layout(set=0,binding=2,r32f) uniform image2D water_state;
layout(set=0,binding=3,rg32f) uniform image2D momentum_state;

layout(set=0,binding=4,r32f) uniform readonly image2D obstacle_state;
layout(set=0,binding=5,std430) buffer Control {uint control[];};
layout(set=0,binding=6,std430) readonly buffer Decision {uint d[];};
layout(set=0,binding=7,std430) readonly buffer Waves {vec4 waves[];};
layout(push_constant,std430) uniform Params {
 float area,mean_level,amplitude,omega;
 uint count,mode;float phase,period;
 uint overflow_enabled;float check_interval,start_level,stop_level;
 float drain_rate,floor_level;uint strip_cells,reserved;
}p;
shared float source[64],sink[64],surface_sum[64];
shared uint wet_count[64],draining;
shared float outlet_level,drain_dt;
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
 bool overflow=p.overflow_enabled!=0u&&p.mode==3u;
 if(lane==0u){draining=overflow?control[26]:0u;outlet_level=level;drain_dt=0.0;}
 barrier();
 if(overflow){
  // 16 x 8 stratified samples of the visible 30 x 15 m rectangle. Dry sand
  // and solid padding cannot raise the estimate of the wet surface level.
  if(time>=uintBitsToFloat(control[27])){
   float sum=0.0;uint count=0u;
   for(uint sample_index=lane;sample_index<128u;sample_index+=64u){
    ivec2 q=ivec2(15u+15u*(sample_index%16u),75u+15u*(sample_index/16u));
    float depth=imageLoad(water_state,q).r;
    if(depth>0.03&&imageLoad(obstacle_state,q).r<0.5){
     sum+=imageLoad(rock_state,q).r+imageLoad(sand_state,q).r+depth;count++;
    }
   }
   surface_sum[lane]=sum;wet_count[lane]=count;barrier();
   for(uint stride=32u;stride>0u;stride>>=1u){
    if(lane<stride){surface_sum[lane]+=surface_sum[lane+stride];wet_count[lane]+=wet_count[lane+stride];}barrier();
   }
   if(lane==0u){
    float mean=wet_count[0]>0u?surface_sum[0]/float(wet_count[0]):0.0;
    if(mean>=p.start_level)draining=1u;
    else if(mean<=p.stop_level)draining=0u;
    if(control[29]==0u&&draining!=0u&&uintBitsToFloat(control[24])==0.0)control[24]=floatBitsToUint(mean);
    control[27]=floatBitsToUint(time+p.check_interval);
    control[28]=floatBitsToUint(mean);control[29]++;
   }
  }
  if(lane==0u){
   drain_dt=max(0.0,time-uintBitsToFloat(control[31]));
   if(draining!=0u)outlet_level=max(p.floor_level,min(level,uintBitsToFloat(control[24])-p.drain_rate*drain_dt));
   control[26]=draining;control[31]=floatBitsToUint(time);
  }
  barrier();
 }
 float added=0.0,removed=0.0;
 for(uint z=lane;z<uint(imageSize(water_state).y);z+=64u){
  if(p.mode==3u&&(z<68u||z>=188u))continue;
  ivec2 q=ivec2(0,z);float old=imageLoad(water_state,q).r;
  float bed=imageLoad(rock_state,q).r+imageLoad(sand_state,q).r;
  float depth=max(0.0,outlet_level-bed),background=max(0.0,outlet_level-wave-bed);
  imageStore(water_state,q,vec4(depth));
  imageStore(momentum_state,q,vec4(depth>0.0?wave*sqrt(9.81*max(background,0.01)):0.0,0.0,0.0,0.0));
  
  float delta=(depth-old)*p.area;added+=max(delta,0.0);removed+=max(-delta,0.0);
  // Negative X is the right-hand sea edge in the authored camera. Taper the
  // sink through the hidden padding into the first 2 m of visible water.
  if(draining!=0u){
   for(uint x=1u;x<p.strip_cells;x++){
    q=ivec2(x,z);if(imageLoad(obstacle_state,q).r>=0.5)continue;
    old=imageLoad(water_state,q).r;
    bed=imageLoad(rock_state,q).r+imageLoad(sand_state,q).r;
    float drop=p.drain_rate*drain_dt*(1.0-smoothstep(0.0,float(p.strip_cells),float(x)));
    depth=max(min(old,max(0.0,p.floor_level-bed)),old-drop);
    float fraction=old>0.0?depth/old:0.0;
    imageStore(water_state,q,vec4(depth));
    imageStore(momentum_state,q,vec4(imageLoad(momentum_state,q).r*fraction,imageLoad(momentum_state,q).g*fraction,0.0,0.0));
    
    removed+=(old-depth)*p.area;
   }
  }
 }
 source[lane]=added;sink[lane]=removed;barrier();
 for(uint stride=32u;stride>0u;stride>>=1u){if(lane<stride){source[lane]+=source[lane+stride];sink[lane]+=sink[lane+stride];}barrier();}
 if(lane==0u){
  control[22]=floatBitsToUint(uintBitsToFloat(control[22])+source[0]);
  control[23]=floatBitsToUint(uintBitsToFloat(control[23])+sink[0]);
  control[24]=floatBitsToUint(outlet_level);control[25]=floatBitsToUint(wave);
  if(draining!=0u)control[30]=floatBitsToUint(uintBitsToFloat(control[30])+sink[0]);
 }
}
