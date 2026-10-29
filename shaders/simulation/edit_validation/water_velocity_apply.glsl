#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) readonly buffer SandCandidate { vec4 sand_cells[]; };
layout(set=0,binding=2,std430) buffer Candidate { vec4 values[]; };
layout(set=0,binding=3,std430) buffer Scratch { int scratch[]; };
layout(set=0,binding=4,std430) buffer Receipt { uint w[]; };
layout(push_constant,std430) uniform Params { uint size; uint x; uint z; uint width; uint height; uint pad0; uint pad1; uint pad2; } params;
void main() {
    uint i=gl_GlobalInvocationID.x,n=params.size,count=n*n;
    if(i>=count||w[0]!=1u) return;
    vec4 old=values[i];
    scratch[i]=floatBitsToInt(old.z);scratch[count+i]=floatBitsToInt(old.w);
    scratch[2u*count+i]=scratch[i];scratch[3u*count+i]=scratch[count+i];
    if(c[21]<2u||uintBitsToFloat(c[27])==0.0||uintBitsToFloat(c[17])==0.0||old.x<=0.001) return;
    uint x=i%n,z=i/n;
    if(x<params.x||z<params.z||x>=params.x+params.width||z>=params.z+params.height||sand_cells[i].x<=0.0) return;
    vec2 p=(vec2(x,z)+0.5-float(n)*0.5)*uintBitsToFloat(c[19]);
    vec2 a=vec2(uintBitsToFloat(c[12]),uintBitsToFloat(c[13]));
    vec2 b=c[11]==0u?a:vec2(uintBitsToFloat(c[14]),uintBitsToFloat(c[15]));
    vec2 segment=b-a;float l2=dot(segment,segment);
    vec2 radial=p-a;
    if(l2>1e-6) {
        float t=dot(radial,segment)/l2;
        if(t>=1.0) radial=p-b;
        else if(t>0.0) {
            // Interior direction is the signed line normal. Subtracting an
            // almost coincident closest point magnifies cancellation error.
            float side=radial.x*segment.y-radial.y*segment.x;
            radial=vec2(segment.y,-segment.x)*sign(side);
        }
    }
    float distance=length(radial);
    vec2 delta=distance>0.0?radial/distance*sand_cells[i].x*uintBitsToFloat(c[27]):vec2(0.0);
    // q+h*delta_u is algebraically identical, and zero components retain their
    // original bits instead of taking a lossy q/h*h round trip.
    vec2 dq=old.x*delta;
    vec2 raw_q=vec2(dq.x==0.0?old.z:old.z+dq.x,dq.y==0.0?old.w:old.w+dq.y);
    vec2 raw_velocity=raw_q/old.x;
    scratch[2u*count+i]=floatBitsToInt(raw_q.x);scratch[3u*count+i]=floatBitsToInt(raw_q.y);
    float speed=length(raw_velocity);
    if(speed>4.0) { raw_q*=4.0/speed; atomicAdd(w[21],1u); }
    values[i].zw=raw_q;
}
