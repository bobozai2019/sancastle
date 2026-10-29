#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,rgba32f) uniform writeonly image2D edge_x;
layout(set=0,binding=1,rgba32f) uniform writeonly image2D edge_z;
layout(set=0,binding=2,r32f) uniform writeonly image2D drain;
layout(set=0,binding=3,r32f) uniform writeonly image2D cfl;
layout(set=0,binding=4,std430) writeonly buffer Slope {uvec2 slope[];};
layout(set=0,binding=5,std430) writeonly buffer Mold {vec2 mold[];};
layout(set=0,binding=6,std430) buffer Flag {uint tagged_flag;};
layout(set=0,binding=7,std430) writeonly buffer Dispatch {uint groups[];};
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);
 if(any(greaterThanEqual(q,ivec2(256))))return;
 imageStore(edge_x,q,vec4(0.375,0.75,1.25,0));
 imageStore(edge_z,q,vec4(-0.625,0.25,0.875,0));
 imageStore(drain,q,vec4(0.125));
 if(all(lessThan(q,imageSize(cfl))))imageStore(cfl,q,vec4(7.25));
 uint i=uint(q.y)*256u+uint(q.x);
 slope[i]=uvec2(floatBitsToUint(0.75),floatBitsToUint(0.375));
 mold[i]=vec2(0.125);
 if(i==0u){tagged_flag=1u;for(uint j=0u;j<6u;j++)groups[j]=1u;}
}
