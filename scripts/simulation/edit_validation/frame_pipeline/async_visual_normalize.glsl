#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,rg32f) uniform readonly image2D foam_src;
layout(set=0,binding=1,rg32f) uniform writeonly image2D foam_dst;
layout(set=0,binding=2,r32f) uniform readonly image2D bed_src;
layout(set=0,binding=3,r32f) uniform writeonly image2D bed_dst;
layout(set=0,binding=4,rgba32f) uniform readonly image2D gravel_src;
layout(set=0,binding=5,rgba32f) uniform writeonly image2D gravel_dst;
layout(set=1,binding=0,std430) buffer Decision {uint d[];};
void main(){
 if(d[4]==2u)return;
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);
 if(all(equal(p,ivec2(0))))d[10]=1u; // visual histories finalized at stable slots
 imageStore(foam_dst,p,imageLoad(foam_src,p));imageStore(bed_dst,p,imageLoad(bed_src,p));
 if(p.x<64&&p.y<16)imageStore(gravel_dst,p,imageLoad(gravel_src,p));
}
