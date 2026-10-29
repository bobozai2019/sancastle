#[compute]
#version 450
layout(local_size_x=64, local_size_y=1, local_size_z=1) in;
layout(rgba32f,set=0,binding=0) uniform readonly image2D previous_state;
layout(rgba32f,set=0,binding=1) uniform writeonly image2D next_state;
layout(r32f,set=0,binding=2) uniform readonly image2D rock;
layout(r32f,set=0,binding=3) uniform readonly image2D sand;
layout(r32f,set=0,binding=4) uniform readonly image2D water;
layout(rg32f,set=0,binding=5) uniform readonly image2D momentum;

layout(push_constant,std430) uniform Params {
    uvec4 identity; // active count, capacity, seed, mode (0=step,1=init,2=reproject,3=drop)
    vec4 domain; // grid size, cell metres, dt, microstep count
    vec4 thresholds; // h_on, h_off, speed_on, speed_off
    vec4 movement; // response_min, response_max, epsilon, effective speed cap
    vec4 spawn; // min_x,min_z,max_x,max_z
    vec4 options; // triangle bed, unused...
} p;
uint hash32(uint v) {
    v ^= v >> 16; v *= 0x7feb352du; v ^= v >> 15;
    v *= 0x846ca68bu; return v ^ (v >> 16);
}
float random01(uint v) { return float(hash32(v) >> 8) / 16777216.0; }
ivec2 safe_cell(ivec2 v) { return clamp(v,ivec2(0),ivec2(int(p.domain.x)-1)); }
float bed_cell(ivec2 v) {
    v=safe_cell(v); return imageLoad(rock,v).r + imageLoad(sand,v).r;
}
vec3 flow_cell(ivec2 v) {
    v=safe_cell(v); return vec3(imageLoad(water,v).r,imageLoad(momentum,v).rg);
}
vec2 cell_at(vec2 xz) {
    return (xz + 0.5*p.domain.x*p.domain.y)/p.domain.y - 0.5;
}
float bed_at(vec2 xz) {
    vec2 cell=cell_at(xz); ivec2 low=ivec2(floor(cell)); vec2 f=fract(cell);
    if (p.options.x<0.5) return bed_cell(ivec2(floor(cell+0.5)));
    float a=bed_cell(low), b=bed_cell(low+ivec2(1,0)), c=bed_cell(low+ivec2(0,1)), d=bed_cell(low+ivec2(1,1));
    return f.x+f.y<=1.0 ? a+f.x*(b-a)+f.y*(c-a) : d+(1.0-f.x)*(c-d)+(1.0-f.y)*(b-d);
}
vec3 flow_at(vec2 xz) {
    vec2 cell=cell_at(xz); ivec2 low=ivec2(floor(cell)); vec2 f=fract(cell);
    return mix(mix(flow_cell(low),flow_cell(low+ivec2(1,0)),f.x),mix(flow_cell(low+ivec2(0,1)),flow_cell(low+ivec2(1,1)),f.x),f.y);
}
float wet_at(float wet, float h) {
    return wet>0.5 ? (h<=p.thresholds.y ? 0.0 : 1.0) : (h>=p.thresholds.x ? 1.0 : 0.0);
}
void main() {
    uint id=gl_GlobalInvocationID.x;
    if (id>=p.identity.y) return;
    ivec2 texel=ivec2(int(id%64u),int(id/64u));
    if (id>=p.identity.x) { imageStore(next_state,texel,vec4(0)); return; }
    vec4 state=imageLoad(previous_state,texel);
    if (p.identity.w==3u && id<uint(p.options.y)) {
        imageStore(next_state,texel,state);
        return;
    }
    if (p.identity.w==1u) {
        state=vec4(mix(p.spawn.x,p.spawn.z,random01(id+p.identity.z)),0.0,mix(p.spawn.y,p.spawn.w,random01(id+p.identity.z+0x9e3779b9u)),0.0);
    }
    if (p.identity.w==3u) {
        float angle=6.28318530718*random01(id+p.identity.z);
        float radius=sqrt(random01(id+p.identity.z+0x9e3779b9u))*0.5*(p.spawn.z-p.spawn.x);
        vec2 position=0.5*(p.spawn.xy+p.spawn.zw)+radius*vec2(cos(angle),sin(angle));
        state=vec4(position.x,0.0,position.y,0.0);
    }
    float response=mix(p.movement.x,p.movement.y,random01(id+p.identity.z+0x85ebca6bu));
    vec2 xz=state.xz;
    int steps=int(p.domain.w);
    for (int i=0;i<steps;i++) {
        vec3 flow=flow_at(xz); float h=max(flow.x,0.0);
        state.w=wet_at(state.w,h);
        if (p.identity.w==0u && state.w>0.5) {
            vec2 velocity=flow.yz/max(h,p.movement.z);
            float speed=length(velocity);
            if (speed>p.movement.w) velocity*=p.movement.w/speed;
            float ramp=smoothstep(p.thresholds.w,p.thresholds.z,min(speed,p.movement.w));
            xz+=response*ramp*velocity*(p.domain.z/float(steps));
            float half_extent=0.5*p.domain.x*p.domain.y;
            xz=clamp(xz,vec2(-half_extent),vec2(half_extent));
        }
    }
    // Reclassify at the destination as well; height matches the visible bed.
    state.w=wet_at(state.w,max(flow_at(xz).x,0.0));
    imageStore(next_state,texel,vec4(xz.x,bed_at(xz),xz.y,state.w));
}
