#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Control {uint control[];};
layout(set=0,binding=1,std430) readonly buffer Stroke {uint stroke[];};
layout(set=0,binding=2,std430) buffer PublishedStroke {uint published_stroke[];};
layout(set=0,binding=3,r32f) uniform readonly image2D source_sediment;
layout(set=0,binding=4,r32f) uniform writeonly image2D view_sediment;
layout(set=0,binding=5,rg32f) uniform readonly image2D source_momentum;
layout(set=0,binding=6,rg32f) uniform writeonly image2D view_momentum;


layout(set=0,binding=7,r16f) uniform readonly image2D source_wetness;
layout(set=0,binding=8,r16f) uniform writeonly image2D view_wetness;
layout(set=0,binding=9,r16f) uniform readonly image2D source_compaction;
layout(set=0,binding=10,r16f) uniform writeonly image2D view_compaction;
layout(set=0,binding=11,rg32f) uniform readonly image2D source_mold_support;
layout(set=0,binding=12,rg32f) uniform writeonly image2D view_mold_support;
layout(set=0,binding=13,rgba32f) uniform readonly image2D source_flux;
layout(set=0,binding=14,rgba32f) uniform writeonly image2D view_flux;
layout(set=0,binding=15,r32f) uniform readonly image2D source_baseline;
layout(set=0,binding=16,r32f) uniform writeonly image2D view_baseline;
void main(){
 if(control[1]!=0u)return;
 uint i=gl_GlobalInvocationID.x;if(i>=65536u)return;ivec2 q=ivec2(i%256u,i/256u);
 imageStore(view_sediment,q,imageLoad(source_sediment,q));
 imageStore(view_momentum,q,vec4(imageLoad(source_momentum,q).rg,0.0,0.0));
 
 imageStore(view_wetness,q,imageLoad(source_wetness,q));
 imageStore(view_compaction,q,imageLoad(source_compaction,q));
 imageStore(view_mold_support,q,imageLoad(source_mold_support,q));
 imageStore(view_flux,q,imageLoad(source_flux,q));
 imageStore(view_baseline,q,imageLoad(source_baseline,q));
 if(i<16u)published_stroke[i]=stroke[i];
}
