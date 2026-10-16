#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=1,std430) readonly buffer Cells {uint v[];};
layout(set=0,binding=2,std430) buffer Candidate {vec4 values[];};
layout(set=0,binding=3,std430) buffer Scratch {int scratch[];};
layout(set=0,binding=4,std430) buffer WaterReceipt {uint w[];};
layout(push_constant,std430) uniform Push {uint n,index,phase,policy,pad0,pad1,pad2,pad3;}p;
void main(){uint i=gl_GlobalInvocationID.x,count=p.n*p.n;if(i>=count||w[0]!=1u)return;vec4 old=values[i];
 scratch[i]=floatBitsToInt(old.z);scratch[count+i]=floatBitsToInt(old.w);scratch[2u*count+i]=scratch[i];scratch[3u*count+i]=scratch[count+i];
 uint k=i*16u;float raised=max(0.0,uintBitsToFloat(v[k+1u])-uintBitsToFloat(v[k]));
 float speed=uintBitsToFloat(c[41]);if(p.policy<2u||speed==0.0||raised==0.0||old.x<=0.001)return;
 vec2 direction=vec2(uintBitsToFloat(v[k+13u]),uintBitsToFloat(v[k+14u]));
 vec2 dq=old.x*direction*raised*speed;
 vec2 raw=vec2(dq.x==0.0?old.z:old.z+dq.x,dq.y==0.0?old.w:old.w+dq.y);
 scratch[2u*count+i]=floatBitsToInt(raw.x);scratch[3u*count+i]=floatBitsToInt(raw.y);
 float velocity=length(raw/old.x);if(velocity>4.0){raw*=4.0/velocity;atomicAdd(w[21],1u);}values[i].zw=raw;
}
