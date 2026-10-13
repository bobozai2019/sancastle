#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(r32f,set=0,binding=0) uniform image2D sand_state;
layout(r32f,set=0,binding=1) uniform image2D water_state;
layout(r32f,set=0,binding=2) uniform image2D qx_state;
layout(r32f,set=0,binding=3) uniform image2D qz_state;
layout(push_constant,std430) uniform Params {
    vec4 segment;
    vec4 brush; // radius, signed height, cell size, water mode
    vec4 bounds; // x, z, grid size, velocity gain
} p;
void main() {
    ivec2 i=ivec2(gl_GlobalInvocationID.xy)+ivec2(p.bounds.xy);
    if(any(greaterThanEqual(i,ivec2(p.bounds.z)))) return;
    vec2 x=(vec2(i)+0.5-p.bounds.z*0.5)*p.brush.z;
    vec2 a=p.segment.xy,b=p.segment.zw,d=b-a;
    vec2 nearest=a+d*clamp(dot(x-a,d)/max(dot(d,d),1e-8),0.0,1.0);
    float w=max(0.0,1.0-length(x-nearest)/p.brush.x);
    if(w==0.0) return;
    float before=imageLoad(sand_state,i).r;
    float after=clamp(before+p.brush.y*w,0.0,4.0);
    imageStore(sand_state,i,vec4(after));
    if(p.brush.w<0.5) return;
    float h=imageLoad(water_state,i).r;
    // Wet cells preserve surface approximately; dry cells never create water.
    float next=h>0.0001?clamp(h-(after-before),0.0,4.0):0.0;
    float qx=imageLoad(qx_state,i).r,qz=imageLoad(qz_state,i).r;
    vec2 velocity=h>0.0001?vec2(qx,qz)/h:vec2(0.0);
    if(p.brush.w>1.5 && next>0.0001) {
        vec2 radial=x-nearest;
        velocity+=radial/max(length(radial),p.brush.z)*sign(p.brush.y)*p.bounds.w*w;
    }
    float speed=length(velocity);
    if(speed>1.0) velocity/=speed;
    imageStore(water_state,i,vec4(next));
    imageStore(qx_state,i,vec4(next*velocity.x));
    imageStore(qz_state,i,vec4(next*velocity.y));
}
