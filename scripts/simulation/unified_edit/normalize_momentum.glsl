#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform readonly image2D water_src;
layout(set=0,binding=1,r32f) uniform writeonly image2D water_dst;
layout(set=0,binding=2,rg32f) uniform readonly image2D momentum_src;
layout(set=0,binding=3,rg32f) uniform writeonly image2D momentum_dst;


layout(set=0,binding=4,r32f) uniform readonly image2D sediment_src;
layout(set=0,binding=5,r32f) uniform writeonly image2D sediment_dst;
layout(set=0,binding=6,r32f) uniform readonly image2D sand_src;
layout(set=0,binding=7,r32f) uniform writeonly image2D sand_dst;
layout(set=0,binding=8,r16f) uniform readonly image2D wetness_src;
layout(set=0,binding=9,r16f) uniform writeonly image2D wetness_dst;
layout(set=0,binding=10,r16f) uniform readonly image2D compact_src;
layout(set=0,binding=11,r16f) uniform writeonly image2D compact_dst;
layout(set=0,binding=12,rgba32f) uniform readonly image2D flux_src;
layout(set=0,binding=13,rgba32f) uniform writeonly image2D flux_dst;
layout(set=1,binding=0,std430) buffer Decision {uint d[];};
void main(){
 if(d[4]==2u)return;
 // Finalize ownership together with the texture transfer. A read-only
 // decision consumer failed to order this transfer on the tested D3D12 path.
 if(all(equal(gl_GlobalInvocationID,uvec3(0))))d[5]=0u;
 if((d[1]&1u)==0u)return;
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);
 imageStore(water_dst,p,imageLoad(water_src,p));imageStore(momentum_dst,p,vec4(imageLoad(momentum_src,p).rg,0.0,0.0));
 imageStore(sediment_dst,p,imageLoad(sediment_src,p));imageStore(sand_dst,p,imageLoad(sand_src,p));
 imageStore(wetness_dst,p,imageLoad(wetness_src,p));imageStore(compact_dst,p,imageLoad(compact_src,p));imageStore(flux_dst,p,imageLoad(flux_src,p));
}
