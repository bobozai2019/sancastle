#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(r32f,set=0,binding=0) uniform readonly image2D bed;
layout(r32f,set=0,binding=1) uniform readonly image2D water;
layout(r32f,set=0,binding=2) uniform readonly image2D qx;
layout(r32f,set=0,binding=3) uniform readonly image2D qz;
layout(rgba32f,set=0,binding=4) uniform writeonly image2D display_state;
layout(set=0,binding=5,std430) readonly buffer Audit {vec4 result[8];};
void main(){if(result[0].w!=0.)return;ivec2 p=ivec2(gl_GlobalInvocationID.xy);imageStore(display_state,p,vec4(imageLoad(bed,p).r,imageLoad(water,p).r,imageLoad(qx,p).r,imageLoad(qz,p).r));}
