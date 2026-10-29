#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Input {uint req[];};
layout(set=0,binding=1,std430) buffer Output {uint res[];};
layout(set=0,binding=2,std430) readonly buffer Stamp {uint stamp[];};
layout(set=0,binding=3,std430) readonly buffer Dirty {uint dirty[];};
layout(set=0,binding=4,r32f) uniform readonly image2D rock;
layout(set=0,binding=5,r32f) uniform readonly image2D sand;
layout(set=0,binding=6,r32f) uniform readonly image2D water;
layout(set=0,binding=7,rg32f) uniform readonly image2D momentum;

layout(set=0,binding=8,r32f) uniform readonly image2D clock_value;
bool finite_value(float v){return !isnan(v)&&!isinf(v);}
bool older(uvec2 a,uvec2 b){return a.y<b.y||(a.y==b.y&&a.x<b.x);}
vec4 cell(ivec2 p){
 p=clamp(p,ivec2(0),ivec2(255));
 return vec4(imageLoad(rock,p).r+imageLoad(sand,p).r,imageLoad(water,p).r,imageLoad(momentum,p).rg);
}
void main(){
 for(uint i=0u;i<800u;i++)res[i]=0u;
 for(uint i=0u;i<32u;i++)res[i]=req[i];
 res[1]=0u;
 if(any(notEqual(uvec2(req[6],req[7]),uvec2(stamp[0],stamp[1]))))res[1]|=1u;
 if(older(uvec2(stamp[2],stamp[3]),uvec2(req[10],req[11])))res[1]|=2u;
 res[10]=stamp[2];res[11]=stamp[3];res[12]=stamp[6];res[13]=stamp[7];res[14]=stamp[4];res[15]=stamp[5];
 res[16]=floatBitsToUint(imageLoad(clock_value,ivec2(0)).r);
 for(uint i=0u;i<req[17]&&i<32u;i++){
  uint a=32u+i*8u,b=32u+i*16u;
  for(uint j=0u;j<7u;j++)res[b+j]=req[a+j];
  vec2 pos=vec2(uintBitsToFloat(req[a+4u]),uintBitsToFloat(req[a+6u]));
  vec2 grid=pos/0.125+127.5;ivec2 low=ivec2(floor(grid));vec2 f=fract(grid);
  vec4 s=mix(mix(cell(low),cell(low+ivec2(1,0)),f.x),mix(cell(low+ivec2(0,1)),cell(low+ivec2(1,1)),f.x),f.y);
  vec2 velocity=s.y>0.001?s.zw/max(s.y,0.005):vec2(0);
  bool valid=finite_value(s.x)&&finite_value(s.y)&&s.y>=0.0&&finite_value(s.z)&&finite_value(s.w)&&finite_value(velocity.x)&&finite_value(velocity.y);
  if(!valid)res[1]|=4u;
  res[b+7u]=floatBitsToUint(s.x);res[b+8u]=floatBitsToUint(s.y);res[b+9u]=floatBitsToUint(s.x+s.y);
  res[b+10u]=floatBitsToUint(velocity.x);res[b+11u]=floatBitsToUint(velocity.y);res[b+12u]=uint(valid);
 }
 for(uint i=0u;i<64u;i++){
  if((req[18u+i/32u]&(1u<<(i%32u)))==0u)continue;
  uint b=544u+i*4u;res[b]=i;res[b+1u]=dirty[i*4u+3u];res[b+2u]=dirty[i*4u+1u];res[b+3u]=dirty[i*4u+2u];
 }
}
