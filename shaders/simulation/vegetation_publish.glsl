#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,rgba32f) uniform readonly image2D roots;
layout(set=0,binding=1,rgba32f) uniform readonly image2D motion;
layout(set=0,binding=2,rgba32f) uniform writeonly image2D roots_view;
layout(set=0,binding=3,rgba32f) uniform writeonly image2D motion_view;
layout(set=0,binding=4,std430) readonly buffer Control {uint control[];};
void main(){
 if(control[1]!=0u)return;
 ivec2 at=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(at,ivec2(128,24))))return;
 imageStore(roots_view,at,imageLoad(roots,at));imageStore(motion_view,at,imageLoad(motion,at));
}
