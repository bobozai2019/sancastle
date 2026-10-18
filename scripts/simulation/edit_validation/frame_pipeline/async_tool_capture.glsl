#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=1,std430) buffer Receipt {uint r[];};
layout(set=0,binding=2,std430) buffer Control {uint control[];};
layout(set=0,binding=3,std430) buffer Completion {uint result[];};
layout(push_constant,std430) uniform Params {uint mode,pad0,pad1,pad2;}p;
void main(){
 r[63]=0u; // begin's private marker is not part of a command receipt.
 bool valid=r[0]==0x32535252u&&r[1]==2u&&r[2]==256u&&r[3]>=1u&&r[3]<=3u;
 for(uint j=0u;j<8u;j++)valid=valid&&r[4u+j]==c[4u+j];
 valid=valid&&r[12]==control[10]&&r[13]==control[11]&&r[18]==c[16]&&r[19]==c[17];
 if(!valid)control[1]|=4u;
 if(valid&&control[1]==0u){
  if(r[3]==1u){
   if(p.mode==1u||p.mode==3u||p.mode==4u){control[10]=r[14];control[11]=r[15];}
   if(p.mode!=0u&&p.mode!=2u)control[18]++;
  }else if(p.mode!=0u&&p.mode!=2u){
   control[19]++;
   if(r[20]==16u||(r[31]&256u)!=0u)control[1]|=8u;
  }
 }
 for(uint j=0u;j<64u;j++)result[20u+j]=r[j];
}
