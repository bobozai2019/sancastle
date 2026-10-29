#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) writeonly buffer Log {uint v[];};
layout(set=0,binding=1,std430) buffer TileHash {uint h[];};
layout(set=1,binding=0,r32f) uniform readonly image2D old_sediment;
layout(set=1,binding=1,r32f) uniform readonly image2D old_water;
layout(set=1,binding=2,rgba32f) uniform readonly image2D flux;
layout(set=1,binding=3,r8) uniform readonly image2D obstacle;
layout(set=1,binding=4,r32f) uniform readonly image2D old_sand;
layout(set=1,binding=5,r16f) uniform readonly image2D old_wet;
layout(set=1,binding=6,r16f) uniform readonly image2D old_compact;
layout(set=1,binding=7,r32f) uniform readonly image2D new_water;
layout(set=1,binding=8,r32f) uniform readonly image2D stage_sand;
layout(set=1,binding=9,r32f) uniform readonly image2D stage_sediment;
layout(set=1,binding=10,r16f) uniform readonly image2D stage_wet;
layout(set=1,binding=11,r16f) uniform readonly image2D stage_compact;
layout(push_constant,std430) uniform Push {uint event_index,phase,tick,revision,index,dt_bits,pixel_count,row_words;}p;
const int X[16]=int[](0,8,16,24,32,40,48,50,52,54,56,64,80,96,112,128);
shared uint work[1920];
uint mix_word(uint a){a^=a>>16u;a*=0x7feb352du;a^=a>>15u;a*=0x846ca68bu;a^=a>>16u;return a;}
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);uint lane=gl_LocalInvocationIndex;
 uint words[15];words[0]=floatBitsToUint(imageLoad(old_sediment,q).x);words[1]=floatBitsToUint(imageLoad(old_water,q).x);
 vec4 f=imageLoad(flux,q);words[2]=floatBitsToUint(f.x);words[3]=floatBitsToUint(f.y);words[4]=floatBitsToUint(f.z);words[5]=floatBitsToUint(f.w);
 words[6]=floatBitsToUint(imageLoad(obstacle,q).x);words[7]=floatBitsToUint(imageLoad(old_sand,q).x);
 words[8]=floatBitsToUint(imageLoad(old_wet,q).x);words[9]=floatBitsToUint(imageLoad(old_compact,q).x);
 words[10]=floatBitsToUint(imageLoad(new_water,q).x);words[11]=floatBitsToUint(imageLoad(stage_sand,q).x);
 words[12]=floatBitsToUint(imageLoad(stage_sediment,q).x);words[13]=floatBitsToUint(imageLoad(stage_wet,q).x);words[14]=floatBitsToUint(imageLoad(stage_compact,q).x);
 uint linear=uint(q.y)*256u+uint(q.x);
 for(uint field=0u;field<15u;field++){
  work[field*128u+lane]=mix_word(words[field]+linear*0x9e3779b9u+field*0x85ebca6bu);
  work[field*128u+64u+lane]=mix_word(words[field]^mix_word(linear+field*0xc2b2ae35u+0x27d4eb2fu));
 }
 barrier();
 for(uint stride=32u;stride>0u;stride>>=1u){
  if(lane<stride){for(uint field=0u;field<15u;field++){work[field*128u+lane]^=work[field*128u+lane+stride];work[field*128u+64u+lane]^=work[field*128u+64u+lane+stride];}}
  barrier();
 }
 if(lane==0u){
  uint tile=uint(q.y)/32u*8u+uint(q.x)/32u;uint base=((p.event_index*3u+p.phase)*64u+tile)*30u;
  for(uint field=0u;field<15u;field++){atomicXor(h[base+field*2u],work[field*128u]);atomicXor(h[base+field*2u+1u],work[field*128u+64u]);}
 }
 int point=-1;for(int j=0;j<16;j++){if(q.x==X[j])point=j;}
 int row=q.y==0?0:(q.y==14?1:(q.y==128?2:-1));if(point<0||row<0)return;
 uint pixel=uint(row*16+point);uint k=((p.event_index*3u+p.phase)*p.pixel_count+pixel)*p.row_words;
 v[k]=p.tick;v[k+1u]=p.revision;v[k+2u]=p.index;v[k+3u]=p.dt_bits;
 v[k+4u]=uint(q.x);v[k+5u]=uint(q.y);v[k+6u]=p.event_index;v[k+7u]=p.phase;
 for(uint field=0u;field<15u;field++)v[k+8u+field]=words[field];v[k+23u]=0u;
}
