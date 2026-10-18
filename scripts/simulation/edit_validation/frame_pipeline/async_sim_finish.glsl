#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Decision {uint d[];};
layout(set=0,binding=1,std430) buffer Control {uint control[];};
void main(){
 if(d[4]==2u||control[1]!=0u)return;
 uint tick=control[6]+1u;control[7]+=uint(tick==0u);control[6]=tick;
 uint revision=control[10]+d[1];control[11]+=uint(revision<control[10]);control[10]=revision;
 float actual_dt=uintBitsToFloat(d[3]);control[8]=floatBitsToUint(uintBitsToFloat(control[8])+actual_dt);control[9]=d[3];
 control[20]=d[1];control[21]=d[4];
}
