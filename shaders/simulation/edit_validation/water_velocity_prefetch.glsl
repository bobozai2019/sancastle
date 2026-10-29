#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) readonly buffer Candidate { vec4 values[]; };
layout(set=0,binding=2,std430) readonly buffer Scratch { int scratch[]; };
layout(set=0,binding=3,std430) buffer Receipt { uint w[]; };
void add(inout float sum,inout float correction,float v) {
    precise float y=v-correction;precise float next=sum+y;correction=(next-sum)-y;sum=next;
}
shared vec4 partial_impulse[64];
shared vec4 partial_energy[64];
shared uint bad;
void main() {
    if(w[0]!=1u) return;
    uint n=c[20],count=n*n;
    float area=uintBitsToFloat(c[19])*uintBitsToFloat(c[19]);
    precise float ix=0.0,ixc=0.0,iz=0.0,izc=0.0,lx=0.0,lxc=0.0,lz=0.0,lzc=0.0,energy=0.0,ec=0.0,removed=0.0,rc=0.0;
    float max_signal=0.01;
    uint lane=gl_LocalInvocationID.x;
    if(lane==0u) bad=0u;barrier();
    for(uint index=lane;index<count;index+=64u) {
        vec4 value=values[index];
        if(any(isnan(value))||any(isinf(value))||value.x<0.0||value.y<0.0) { atomicOr(bad,1u);continue; }
        vec2 before=vec2(intBitsToFloat(scratch[index]),intBitsToFloat(scratch[count+index]));
        vec2 raw=vec2(intBitsToFloat(scratch[2u*count+index]),intBitsToFloat(scratch[3u*count+index]));
        add(ix,ixc,(value.z-before.x)*area);add(iz,izc,(value.w-before.y)*area);
        add(lx,lxc,(raw.x-value.z)*area);add(lz,lzc,(raw.y-value.w)*area);
        if(value.x>0.001) {
            add(energy,ec,0.5*(dot(raw,raw)-dot(before,before))/value.x*area);
            add(removed,rc,0.5*(dot(raw,raw)-dot(value.zw,value.zw))/value.x*area);
            max_signal=max(max_signal,max(abs(value.z),abs(value.w))/max(value.x,0.005)+sqrt(9.81*value.x));
        }
    }
    partial_impulse[lane]=vec4(ix,iz,lx,lz);
    partial_energy[lane]=vec4(energy,removed,max_signal,0.0);
    barrier();
    if(lane!=0u) return;
    if(bad!=0u) { w[0]=2u;w[1]=4u;return; }
    ix=0.0;ixc=0.0;iz=0.0;izc=0.0;lx=0.0;lxc=0.0;lz=0.0;lzc=0.0;energy=0.0;ec=0.0;removed=0.0;rc=0.0;max_signal=0.01;
    for(uint index=0u;index<64u;index++) {
        vec4 impulse=partial_impulse[index];
        vec4 summary=partial_energy[index];
        add(ix,ixc,impulse.x);add(iz,izc,impulse.y);add(lx,lxc,impulse.z);add(lz,lzc,impulse.w);
        add(energy,ec,summary.x);add(removed,rc,summary.y);max_signal=max(max_signal,summary.z);
    }
    w[17]=floatBitsToUint(ix);w[18]=floatBitsToUint(iz);w[19]=floatBitsToUint(lx);w[20]=floatBitsToUint(lz);
    w[22]=floatBitsToUint(energy);w[23]=floatBitsToUint(removed);w[24]=floatBitsToUint(energy-removed);
    w[30]=floatBitsToUint(max_signal);
    // Combine the fixed 30Hz scale first. At 0.125m cells the divisor is
    // exactly 1.3125; evaluating dt*signal first misclassifies 84 as 65 steps.
    precise float divisor=30.0*0.35*uintBitsToFloat(c[19]);
    float steps=ceil(max_signal/divisor);
    w[31]=(!isnan(steps)&&!isinf(steps)&&steps<4294967040.0)?uint(steps):4294967295u;
    if(isnan(steps)||isinf(steps)||steps>64.0||isnan(energy)||isinf(energy)||isnan(removed)||isinf(removed)) { w[0]=2u;w[1]=16u; }
}
