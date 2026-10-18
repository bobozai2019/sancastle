#[compute]
#version 450
layout(local_size_x=64) in;
// Per chunk: state(clean=0/dirty=1/borrowed=2), last dirty state_seq low/high.
// A borrowed chunk remains reserved when a newer work unit changes it.
layout(set=0,binding=0,std430) buffer Dirty {uint dirty[];};
layout(set=0,binding=1,std430) readonly buffer Control {uint control[];};
layout(set=0,binding=2,r32f) uniform image2D before_sand;
layout(set=0,binding=3,r32f) uniform readonly image2D sand;
layout(set=0,binding=4,r32f) uniform readonly image2D rock;
layout(set=0,binding=5,std430) buffer Snapshot {uint data[];};
layout(push_constant,std430) uniform Params {uint mode,glo,ghi,slo,shi,pad0,pad1,pad2;}p;
void mark(uint chunk){
 atomicCompSwap(dirty[chunk*4u],0u,1u);
 atomicExchange(dirty[chunk*4u+1u],control[4]);atomicExchange(dirty[chunk*4u+2u],control[5]);
}
bool newer(uvec2 a,uvec2 b){return a.y>b.y||(a.y==b.y&&a.x>b.x);}
void main(){
 uint lane=gl_GlobalInvocationID.x;
 if(p.mode==0u){if(lane<64u)mark(lane);return;}
 if(p.mode==1u){if(lane<65536u){ivec2 q=ivec2(lane%256u,lane/256u);imageStore(before_sand,q,imageLoad(sand,q));}return;}
 if(p.mode==2u){
  if(lane>=65536u||control[1]!=0u)return;
  uint x=lane%256u,z=lane/256u;ivec2 q=ivec2(x,z);
  if(imageLoad(before_sand,q).r==imageLoad(sand,q).r)return;
  uint chunk=(z/32u)*8u+x/32u;mark(chunk);
  if(x>0u&&x%32u==0u)mark(chunk-1u);
  if(z>0u&&z%32u==0u)mark(chunk-8u);
  if(x>0u&&z>0u&&x%32u==0u&&z%32u==0u)mark(chunk-9u);
  return;
 }
 if(p.mode==3u){
  if(lane!=0u)return;
  for(uint j=0u;j<32u;j++)data[j]=0u;
  data[0]=2u;data[1]=control[1];data[2]=p.glo;data[3]=p.ghi;data[4]=p.slo;data[5]=p.shi;
  data[6]=control[4];data[7]=control[5];data[8]=control[6];data[9]=control[7];
  data[11]=33u;data[12]=256u;data[13]=floatBitsToUint(0.125);data[15]=control[10];
  // Revision high word lives in the fixed trailer after the 16 chunk payloads.
  data[32u+16u*1089u]=control[11];
  if(control[2]!=p.glo||control[3]!=p.ghi)data[1]|=2u;
  if(data[1]!=0u)return;
  uint cursor=dirty[256],count=0u;
  for(uint j=0u;j<64u&&count<16u;j++){
   uint chunk=(cursor+j)%64u;
   if(dirty[chunk*4u]!=1u)continue;
   dirty[chunk*4u]=2u;data[16u+count++]=chunk;dirty[256]=(chunk+1u)%64u;
  }
  data[10]=count;data[14]=count*1089u*4u;return;
 }
 if(p.mode==4u){
  if(data[1]!=0u||lane>=data[10]*1089u)return;
  uint slot=lane/1089u,index=lane%1089u,chunk=data[16u+slot];
  ivec2 q=ivec2((chunk%8u)*32u+index%33u,(chunk/8u)*32u+index/33u);
  q=min(q,ivec2(255));data[32u+lane]=floatBitsToUint(imageLoad(rock,q).r+imageLoad(sand,q).r);return;
 }
 if(p.mode==5u||p.mode==6u){
  if(lane>=data[10])return;
  uint chunk=data[16u+lane],base=chunk*4u;
  if(chunk>=64u)return;
  uvec2 last=uvec2(dirty[base+1u],dirty[base+2u]),captured=uvec2(data[6],data[7]);
  dirty[base]=(p.mode==6u||newer(last,captured))?1u:0u;
 }
}
