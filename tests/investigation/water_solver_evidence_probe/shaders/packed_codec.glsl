#[compute]
#version 450
// Codec contract only. This is not any original solver stage.
layout(local_size_x=32,local_size_y=32,local_size_z=1) in;
layout(set=0,binding=0,std430) readonly buffer Input { uvec4 input_words[]; };
layout(set=0,binding=1,std430) writeonly buffer Output { uvec4 output_words[]; };
layout(set=0,binding=2,std430) writeonly buffer Codes { uint codes[]; };
void main() {
 uint x=gl_GlobalInvocationID.x,y=gl_GlobalInvocationID.y;
 if(x>=512u || y>=256u) return;
 uint i=y*512u+x;
 uvec4 p=input_words[i];
 uint nx=p.x&255u,nz=(p.x>>8u)&255u;
 uint vx=(p.x>>16u)|((p.y&255u)<<16u),vz=p.y>>8u;
 uint amount=p.z&0xffffffu,bed=(p.z>>24u)|((p.w&65535u)<<8u);
 uint foam=(p.w>>16u)&255u,source=(p.w>>24u)&15u,sea=p.w>>28u;
 uint k=i*9u;
 codes[k]=nx;codes[k+1u]=nz;codes[k+2u]=vx;codes[k+3u]=vz;
 codes[k+4u]=amount;codes[k+5u]=bed;codes[k+6u]=foam;codes[k+7u]=source;codes[k+8u]=sea;
 output_words[i]=uvec4(nx|(nz<<8u)|(vx<<16u),(vx>>16u)|(vz<<8u),
                       amount|(bed<<24u),(bed>>8u)|(foam<<16u)|(source<<24u)|(sea<<28u));
}
