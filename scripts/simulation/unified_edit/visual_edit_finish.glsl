#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,rgba32f) uniform readonly image2D gravel_src;
layout(set=0,binding=1,rgba32f) uniform writeonly image2D gravel_dst;
layout(set=0,binding=2,std430) readonly buffer Control {uint control[];};
void main(){
 if(control[1]!=0u)return;
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);
 if(q.x<64&&q.y<16)imageStore(gravel_dst,q,imageLoad(gravel_src,q));
}
