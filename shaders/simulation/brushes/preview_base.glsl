#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,r32f) uniform readonly image2D rock;
layout(set=0,binding=1,r32f) uniform readonly image2D sand0;
layout(set=0,binding=2,r32f) uniform readonly image2D sand1;
layout(set=0,binding=3,r32f) uniform readonly image2D water0;
layout(set=0,binding=4,r32f) uniform readonly image2D water1;
layout(set=0,binding=5,r8) uniform readonly image2D obstacle;
layout(set=0,binding=6,rgba32f) uniform readonly image2D castle_template;
layout(set=0,binding=7,std430) writeonly buffer Summary {uint result[];};
layout(push_constant,std430) uniform Push {vec4 center_yaw_scale;vec4 height_index_unused;}p;
void main(){
 for(uint i=0u;i<16u;i++)result[i]=0u;
 float scale=p.center_yaw_scale.w,yaw=p.center_yaw_scale.z,co=cos(yaw),si=sin(yaw),radius=2.0*scale*(abs(co)+abs(si));
 vec2 center=p.center_yaw_scale.xy;
 ivec2 lo=clamp(ivec2(floor((center-radius)/0.125+127.5)),ivec2(0),ivec2(255));
 ivec2 hi=clamp(ivec2(ceil((center+radius)/0.125+127.5)),ivec2(0),ivec2(255));
 float high=-3.402823466e38,low=3.402823466e38,maxwater=0.0;uint count=0u,flags=0u;
 for(int z=lo.y;z<=hi.y;z++)for(int x=lo.x;x<=hi.x;x++){
  vec2 world=(vec2(x,z)+0.5-128.0)*0.125-center;
  vec2 local=vec2(co*world.x+si*world.y,-si*world.x+co*world.y)/scale;
  if(any(lessThan(local,vec2(-2)))||any(greaterThan(local,vec2(2))))continue;
  ivec2 sample_point=ivec2(floor((local+2.0)*16.0+0.5));if(imageLoad(castle_template,sample_point).y<0.5)continue;
  ivec2 cell=ivec2(x,z);float sand=p.height_index_unused.y<0.5?imageLoad(sand0,cell).x:imageLoad(sand1,cell).x;
  float water=p.height_index_unused.y<0.5?imageLoad(water0,cell).x:imageLoad(water1,cell).x;
  float bed=imageLoad(rock,cell).x+sand;
  if(isnan(bed)||isinf(bed)||sand<0.0)flags|=256u;
  high=max(high,bed);low=min(low,bed);maxwater=max(maxwater,water);count++;
 }
 if(count==0u)flags|=4096u;
 result[0]=floatBitsToUint(0.0);result[1]=floatBitsToUint(low);result[2]=flags;result[3]=floatBitsToUint(maxwater);result[4]=count;
}
