#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Input { uint input_words[]; };
layout(set=0,binding=1,std430) buffer Control { uint control[]; };
layout(set=0,binding=2,std430) writeonly buffer Completion { uint result[]; };
layout(set=0,binding=3,r32f) uniform writeonly image2D completed_clock;
void main() {
    // Called after all passes of a complete work unit, on the same RD stream.
    uint low=control[4]+1u;
    control[5]+=uint(low==0u);
    control[4]=low;
    for(uint j=0u;j<20u;j++) result[j]=0u;
    result[0]=1u;result[1]=control[1];
    result[2]=control[2];result[3]=control[3];
    result[4]=input_words[4];result[5]=input_words[5];
    result[6]=input_words[6];result[8]=input_words[8];result[9]=input_words[9];
    result[10]=control[4];result[11]=control[5];
    result[12]=control[6];result[13]=control[7];
    result[14]=control[8];result[15]=control[9];
    result[16]=control[10];result[17]=control[11];
    result[18]=control[18];result[19]=control[19];
    imageStore(completed_clock,ivec2(0),vec4(uintBitsToFloat(control[8])));
    if(input_words[0]!=1u || input_words[2]!=control[2] || input_words[3]!=control[3]) result[1]|=1u;
}
