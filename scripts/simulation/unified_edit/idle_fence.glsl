#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Proof {uint proof[];};
layout(push_constant,std430) uniform Params {uint low,high,pad0,pad1;}p;
void main(){proof[0]=0x31464c49u;proof[1]=0u;proof[2]=p.low;proof[3]=p.high;}
