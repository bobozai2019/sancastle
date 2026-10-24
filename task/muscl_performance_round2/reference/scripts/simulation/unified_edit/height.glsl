#[compute]
#version 450
layout(local_size_x=64) in;
// Per chunk: state(clean=0/dirty=1/borrowed=2), last dirty state_seq low/high,
// float32 bits of an outward-rounded cumulative maximum bed-change bound.
// A borrowed chunk remains reserved when a newer work unit changes it.
layout(set=0,binding=0,std430) buffer Dirty {uint dirty[];};
layout(set=0,binding=1,std430) readonly buffer Control {uint control[];};
layout(set=0,binding=2,r32f) uniform image2D before_sand;
layout(set=0,binding=3,r32f) uniform readonly image2D sand;
layout(set=0,binding=4,r32f) uniform readonly image2D rock;
layout(set=0,binding=5,std430) buffer Snapshot {uint data[];};
layout(push_constant,std430) uniform Params {uint mode,glo,ghi,slo,shi,priority_lo,priority_hi,pad2;}p;
shared uint change_max[64];
void mark(uint chunk){
 atomicCompSwap(dirty[chunk*4u],0u,1u);
 atomicExchange(dirty[chunk*4u+1u],control[4]);atomicExchange(dirty[chunk*4u+2u],control[5]);
}
bool newer(uvec2 a,uvec2 b){return a.y>b.y||(a.y==b.y&&a.x>b.x);}
uint chunk_tag(uint chunk){
 // Low six bits identify the chunk; the remaining bits encode its cumulative
 // bound rounded upward to a64-ULP float32 boundary. Wire capacity is unchanged.
 uint bits=min(dirty[chunk*4u+3u],0x7f800000u);
 return min((bits+63u)&0xffffffc0u,0x7f800000u)|chunk;
}
void main(){
 uint lane=gl_GlobalInvocationID.x;
 if(p.mode==0u){if(lane<64u)mark(lane);return;}
 if(p.mode==1u){if(lane<65536u){ivec2 q=ivec2(lane%256u,lane/256u);imageStore(before_sand,q,imageLoad(sand,q));}return;}
 if(p.mode==2u){
  uint chunk=gl_WorkGroupID.x,local=gl_LocalInvocationID.x;
  if(chunk>=64u||control[1]!=0u)return;
  uint maximum=0u;
  // Same 33x33 vertices as the actual HeightMap, including its shared halo.
  for(uint index=local;index<1089u;index+=64u){
   ivec2 q=min(ivec2((chunk%8u)*32u+index%33u,(chunk/8u)*32u+index/33u),ivec2(255));
   float delta=abs(imageLoad(sand,q).r-imageLoad(before_sand,q).r);
   uint bits=(isnan(delta)||isinf(delta))?0x7f800000u:floatBitsToUint(delta);
   maximum=max(maximum,bits);
  }
  change_max[local]=maximum;barrier();
  for(uint stride=32u;stride>0u;stride>>=1u){if(local<stride)change_max[local]=max(change_max[local],change_max[local+stride]);barrier();}
  if(local==0u&&change_max[0]>0u){
   mark(chunk);
   // Round subtraction and accumulation upward. Positive infinity means an
   // unknown bound; clients then require the newest collision version.
   float increment=uintBitsToFloat(min(0x7f800000u,change_max[0]+1u));
   float total=uintBitsToFloat(dirty[chunk*4u+3u])+increment;
   dirty[chunk*4u+3u]=min(0x7f800000u,floatBitsToUint(total)+1u);
  }
  return;
 }
 if(p.mode==3u){
  if(lane!=0u)return;
  for(uint j=0u;j<32u;j++)data[j]=0u;
  data[0]=3u;data[1]=control[1];data[2]=p.glo;data[3]=p.ghi;data[4]=p.slo;data[5]=p.shi;
  data[6]=control[4];data[7]=control[5];data[8]=control[6];data[9]=control[7];
  data[11]=33u;data[12]=256u;data[13]=floatBitsToUint(0.125);data[15]=control[10];
  // Revision high word lives in the fixed trailer after the 16 chunk payloads.
  data[32u+16u*1089u]=control[11];
  if(control[2]!=p.glo||control[3]!=p.ghi)data[1]|=2u;
  if(data[1]!=0u)return;
  uint cursor=dirty[256],count=0u;
  if((p.priority_lo|p.priority_hi)!=0u){
   for(uint chunk=0u;chunk<64u&&count<12u;chunk++){
    uint mask=chunk<32u?p.priority_lo:p.priority_hi;
    if((mask&(1u<<(chunk%32u)))==0u||dirty[chunk*4u]!=1u)continue;
    dirty[chunk*4u]=2u;data[16u+count++]=chunk_tag(chunk);
   }
  }
  // With live footprints, smaller complete batches bound main-thread shape
  // installation latency. Priority can still occupy up to twelve entries;
  // the sixteen-entry wire capacity and ordinary zero-mask path stay intact.
  uint target=(p.priority_lo|p.priority_hi)!=0u?min(16u,count+4u):16u;
  for(uint j=0u;j<64u&&count<target;j++){
   uint chunk=(cursor+j)%64u;
   if(dirty[chunk*4u]!=1u)continue;
   dirty[chunk*4u]=2u;data[16u+count++]=chunk_tag(chunk);dirty[256]=(chunk+1u)%64u;
  }
  data[10]=count;data[14]=count*1089u*4u;return;
 }
 if(p.mode==4u){
  if(data[1]!=0u||lane>=data[10]*1089u)return;
  uint slot=lane/1089u,index=lane%1089u,chunk=data[16u+slot]&63u;
  ivec2 q=ivec2((chunk%8u)*32u+index%33u,(chunk/8u)*32u+index/33u);
  q=min(q,ivec2(255));data[32u+lane]=floatBitsToUint(imageLoad(rock,q).r+imageLoad(sand,q).r);return;
 }
 if(p.mode==5u||p.mode==6u){
  if(lane>=data[10])return;
  uint chunk=data[16u+lane]&63u,base=chunk*4u;
  if(chunk>=64u)return;
  uvec2 last=uvec2(dirty[base+1u],dirty[base+2u]),captured=uvec2(data[6],data[7]);
  dirty[base]=(p.mode==6u||newer(last,captured))?1u:0u;
 }
}
