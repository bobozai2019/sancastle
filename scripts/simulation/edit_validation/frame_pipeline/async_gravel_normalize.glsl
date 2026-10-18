#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,rgba32f) uniform readonly image2D source_state;
layout(set=0,binding=1,rgba32f) uniform writeonly image2D target_state;
layout(set=0,binding=2,std430) readonly buffer Control {uint control[];};
layout(push_constant,std430) uniform Params {uint pad0,pad1,pad2,pad3;}p;
void main(){
 uint i=gl_GlobalInvocationID.x;if(i>=1024u||control[1]!=0u)return;
 ivec2 q=ivec2(i%64u,i/64u);imageStore(target_state,q,imageLoad(source_state,q));
}
