#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Control {uint control[];};
layout(set=0,binding=1,std430) buffer Stamp {uint stamp[];};
layout(set=0,binding=2,r32f) uniform readonly image2D sand;
layout(set=0,binding=3,r32f) uniform readonly image2D water;
layout(set=0,binding=4,r32f) uniform writeonly image2D visible_sand;
layout(set=0,binding=5,r32f) uniform writeonly image2D visible_water;
void main(){
 if(control[1]!=0u)return;
 uint i=gl_GlobalInvocationID.x;
 if(i>=65536u)return;
 ivec2 q=ivec2(i%256u,i/256u);
 imageStore(visible_sand,q,imageLoad(sand,q));imageStore(visible_water,q,imageLoad(water,q));
 if(i==0u){
  stamp[0]=control[2];stamp[1]=control[3];stamp[2]=control[4];stamp[3]=control[5];
  stamp[4]=control[10];stamp[5]=control[11];stamp[6]=control[6];stamp[7]=control[7];
 }
}
