#[compute]
#version 450
// UE_VISUAL_DEFINES
layout(local_size_x=8,local_size_y=8) in;
#if UE_FOAM
layout(set=0,binding=0,rg32f) uniform readonly image2D foam_src;
layout(set=0,binding=1,rg32f) uniform writeonly image2D foam_dst;
layout(set=0,binding=2,r32f) uniform readonly image2D bed_src;
layout(set=0,binding=3,r32f) uniform writeonly image2D bed_dst;
#endif
#if UE_GRAVEL
layout(set=0,binding=UE_GBASE,rgba32f) uniform readonly image2D gravel_src;
layout(set=0,binding=UE_GBASE+1,rgba32f) uniform writeonly image2D gravel_dst;
#endif
void main(){
 if(async_d[4]==2u)return;
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);
#if UE_FOAM
 imageStore(foam_dst,q,imageLoad(foam_src,q));imageStore(bed_dst,q,imageLoad(bed_src,q));
#endif
#if UE_GRAVEL
 if(q.x<64&&q.y<16)imageStore(gravel_dst,q,imageLoad(gravel_src,q));
#endif
}
