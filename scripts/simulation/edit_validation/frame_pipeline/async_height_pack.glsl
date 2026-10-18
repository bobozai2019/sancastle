#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,r32f) uniform readonly image2D rock_state;
layout(set=0,binding=1,r32f) uniform readonly image2D sand_state;
layout(set=0,binding=2,std430) writeonly buffer Snapshot {uint data[];};
layout(set=0,binding=3,std430) readonly buffer ChunkIds {uint ids[];};
layout(set=1,binding=0,std430) readonly buffer Control {uint control[];};
layout(push_constant,std430) uniform Params {uvec4 identity;uint count,grid;float cell;uint pad;}p;
void main(){
 uint lane=gl_GlobalInvocationID.x;
 if(lane==0u){
  for(uint j=0u;j<32u;j++)data[j]=0u;
  data[0]=1u;data[1]=control[1];data[2]=p.identity.x;data[3]=p.identity.y;
  data[4]=p.identity.z;data[5]=p.identity.w;data[6]=control[4];data[7]=control[5];data[8]=control[6];data[9]=control[7];
  data[10]=p.count;data[11]=33u;data[12]=p.grid;data[13]=floatBitsToUint(p.cell);data[14]=p.count*1089u*4u;
  for(uint j=0u;j<p.count;j++)data[16u+j]=ids[j];
 }
 if(lane>=p.count*1089u)return;
 uint slot=lane/1089u,sample_index=lane%1089u,chunk=ids[slot],per_row=p.grid/32u;
 ivec2 cell=ivec2((chunk%per_row)*32u+sample_index%33u,(chunk/per_row)*32u+sample_index/33u);
 cell=min(cell,ivec2(p.grid-1u));
 data[32u+lane]=floatBitsToUint(imageLoad(rock_state,cell).r+imageLoad(sand_state,cell).r);
}
