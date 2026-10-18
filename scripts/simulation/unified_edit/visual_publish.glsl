#[compute]
#version 450
// UE_VISUAL_DEFINES
layout(local_size_x=8,local_size_y=8) in;
#if UE_FOAM
layout(set=0,binding=0,rg32f) uniform readonly image2D foam_src;
layout(set=0,binding=1,rg32f) uniform writeonly image2D foam_view;
#endif
#if UE_FRONT
layout(set=0,binding=UE_FBASE,rg32f) uniform readonly image2D front_src;
layout(set=0,binding=UE_FBASE+1,rg32f) uniform writeonly image2D front_view;
#endif
#if UE_GRAVEL
layout(set=0,binding=UE_PGBASE,rgba32f) uniform readonly image2D gravel_src;
layout(set=0,binding=UE_PGBASE+1,rgba32f) uniform writeonly image2D gravel_view;
#endif
layout(set=0,binding=UE_CONTROL,std430) readonly buffer Control {uint control[];};
void main(){
 if(control[1]!=0u)return;
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);
#if UE_FOAM
 imageStore(foam_view,q,imageLoad(foam_src,q));
#endif
#if UE_FRONT
 imageStore(front_view,q,imageLoad(front_src,q));
#endif
#if UE_GRAVEL
 if(q.x<64&&q.y<16)imageStore(gravel_view,q,imageLoad(gravel_src,q));
#endif
}
