#[compute]
#version 450
// Probe only. Preserve the first actual fallback's input before the generic pass.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Input { vec4 input_cells[]; };
layout(set=0,binding=1,std430) readonly buffer Receipt { uint receipt[]; };
layout(set=0,binding=2,std430) readonly buffer Indirect { uint groups[]; };
layout(set=0,binding=3,std430) buffer Evidence { uint words[]; };
layout(push_constant,std430) uniform Params { uint mode,serial,pad0,pad1; } p;
void main() {
 uint i=gl_GlobalInvocationID.x;
 if(p.mode==0u) {
  if(i==0u&&words[0]==0u&&receipt[27]!=1u&&groups[0]!=0u) {
   words[0]=p.serial;words[1]=groups[0];
   for(uint j=0u;j<32u;j++)words[4u+j]=receipt[j];
  }
  return;
 }
 if(words[0]!=p.serial)return;
 if(i<131072u) {
  uvec4 value=floatBitsToUint(input_cells[i]);
  for(uint j=0u;j<4u;j++)words[36u+i*4u+j]=value[j];
 }
}
