#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform readonly image2D water_state;
layout(set=0,binding=1,r32f) uniform readonly image2D sand_state;
layout(set=0,binding=2,r32f) uniform readonly image2D sediment_state;
layout(set=0,binding=3,r32f) uniform readonly image2D qx_state;
layout(set=0,binding=4,r32f) uniform readonly image2D qz_state;
layout(set=0,binding=5,r32f) uniform readonly image2D initial_water;
layout(set=0,binding=6,std430) buffer Monitor { uint counters[]; };
void main(){
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(p,imageSize(water_state))))return;
    float h=imageLoad(water_state,p).r,s=imageLoad(sand_state,p).r;
    float c=imageLoad(sediment_state,p).r,qx=imageLoad(qx_state,p).r,qz=imageLoad(qz_state,p).r;
    vec4 v=vec4(h,s,c,qx);
    bool finite_state=!any(isnan(v))&&!any(isinf(v))&&!isnan(qz)&&!isinf(qz);
    if(!finite_state)atomicOr(counters[1],1u);
    if(h<0.0||s<0.0||c<0.0)atomicOr(counters[1],2u);
    if(finite_state)atomicMax(counters[0],floatBitsToUint(abs(h-imageLoad(initial_water,p).r)));
    if(all(equal(p,ivec2(0))))atomicAdd(counters[2],1u);
}
