#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) readonly buffer StagedSlope {uvec2 result_bits[];};
layout(r16f,set=0,binding=1) uniform restrict readonly image2D wetness_src;
layout(r16f,set=0,binding=2) uniform restrict readonly image2D compaction_src;
layout(r16f,set=0,binding=3) uniform restrict writeonly image2D wetness_dst;
layout(r16f,set=0,binding=4) uniform restrict writeonly image2D compaction_dst;
layout(r32f,set=0,binding=5) uniform restrict writeonly image2D sand0;
layout(r32f,set=0,binding=6) uniform restrict writeonly image2D sand1;
layout(set=0,binding=7,std430) readonly buffer SupportResult {vec2 support_result[];};
layout(set=0,binding=8,std430) readonly buffer Active {uint has_tagged_sand;};
layout(rg32f,set=0,binding=9) uniform restrict writeonly image2D support0;
layout(rg32f,set=0,binding=10) uniform restrict writeonly image2D support1;

// Consume the completed slope SSBO in a separate dispatch. Do not fuse its producer.
void main(){
 ivec2 p=ivec2(gl_GlobalInvocationID.xy),extent=imageSize(sand0);
 if(any(greaterThanEqual(p,extent)))return;
 uint index=uint(p.y*extent.x+p.x);
 float value=max(uintBitsToFloat(result_bits[index].y),0.0);
 imageStore(wetness_dst,p,vec4(imageLoad(wetness_src,p).r,0,0,1));
 imageStore(compaction_dst,p,vec4(imageLoad(compaction_src,p).r,0,0,1));
 imageStore(sand0,p,vec4(value,0,0,1));imageStore(sand1,p,vec4(value,0,0,1));
 vec2 support=has_tagged_sand==0u?vec2(0):support_result[index];
 imageStore(support0,p,vec4(support,0,0));imageStore(support1,p,vec4(support,0,0));
}
