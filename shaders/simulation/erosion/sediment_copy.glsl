#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform restrict readonly image2D sediment_src;
layout(set=0,binding=1,r32f) uniform restrict writeonly image2D sediment_dst;
layout(set=1,binding=0,std430) buffer AsyncDecision {uint async_d[];};
void main(){
 if(async_d[4]==2u)return;
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);
 if(all(equal(p,ivec2(0))))async_d[5]=0u;
 imageStore(sediment_dst,p,imageLoad(sediment_src,p));
}
