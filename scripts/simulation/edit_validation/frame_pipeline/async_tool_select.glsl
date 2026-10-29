#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Input {uint words[];};
layout(set=0,binding=1,std430) buffer Command {uint c[];};
layout(set=0,binding=2,std430) buffer Receipt {uint r[];};
layout(set=0,binding=3,std430) buffer Control {uint control[];};
layout(set=0,binding=4,std430) buffer Stroke {uint stroke[];};
layout(push_constant,std430) uniform Params {uint mode,inject_failure,pad0,pad1;}p;
bool same64(uint a,uint b,uint x,uint y){return a==x&&b==y;}
void main(){
 for(uint j=0u;j<64u;j++){c[j]=words[16u+j];r[j]=0u;}
 bool valid=words[0]==1u&&words[1]==1u&&words[10]==1u&&words[11]==256u&&same64(words[2],words[3],control[2],control[3])
  &&c[0]==0x32535242u&&c[1]==2u&&c[2]==256u&&same64(c[10],c[11],control[2],control[3]);
 if(!valid)control[1]|=2u;
 c[14]=control[10];c[15]=control[11];c[18]=control[6];c[19]=control[7];
 r[0]=0x32535252u;r[1]=2u;r[2]=256u;r[3]=p.mode==1u?0u:1u;
 for(uint j=0u;j<8u;j++)r[4u+j]=c[4u+j];
 r[12]=r[14]=control[10];r[13]=r[15]=control[11];
 r[16]=control[6];r[17]=control[7];r[18]=c[16];r[19]=c[17];r[21]=c[20];
 bool matches=same64(stroke[0],stroke[1],c[8],c[9])&&same64(stroke[2],stroke[3],c[16],c[17]);
 if(p.mode==0u){
  if(stroke[5]!=0u)valid=false;
  if(valid&&control[1]==0u){stroke[0]=c[8];stroke[1]=c[9];stroke[2]=c[16];stroke[3]=c[17];stroke[4]=0u;stroke[5]=1u;stroke[6]=0u;}
 }else if(p.mode==1u){
  if(!matches||stroke[5]!=1u||(stroke[6]!=0u&&c[20]<=stroke[4]))valid=false;
  if(valid){stroke[4]=c[20];stroke[6]=1u;}
 }else if(p.mode==2u){
  if(!matches||stroke[5]!=1u)valid=false;
  if(valid)stroke[5]=0u;
 }
 if(!valid){control[1]|=2u;r[20]=5u;}
 if(control[1]!=0u||p.inject_failure!=0u){r[20]=16u;r[3]=3u;}
 control[9]=0u;
}
