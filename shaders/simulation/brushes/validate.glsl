#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Command {uint c[];};
layout(set=0,binding=1,std430) buffer Receipt {uint r[];};
layout(set=0,binding=3,std430) readonly buffer Scratch {uint s[];};
layout(push_constant,std430) uniform Push {uint n,x,z,w,h,index,phase,reserved;}p;
void add(float value,inout float sum,inout float correction){float y=value-correction;float t=sum+y;correction=(t-sum)-y;sum=t;}
void main(){float volume=0,q=0,a=0,t0=0,t1=0,t2=0,maxdelta=0,removed=0,left=0,right=0,t3=0,t4=0,t5=0;uint count=0,touched=0,minx=p.n,minz=p.n,maxx=0,maxz=0,lo=0,hi=0,flags=0;
 for(uint block=0;block<256u;block++){uint k=block*16u;add(uintBitsToFloat(s[k]),volume,t0);add(uintBitsToFloat(s[k+2]),q,t1);add(uintBitsToFloat(s[k+3]),a,t2);add(uintBitsToFloat(s[k+1]),removed,t3);add(uintBitsToFloat(s[k+14]),left,t4);add(uintBitsToFloat(s[k+15]),right,t5);count+=s[k+5];touched+=s[k+13];minx=min(minx,s[k+6]);minz=min(minz,s[k+7]);maxx=max(maxx,s[k+8]);maxz=max(maxz,s[k+9]);lo|=s[k+10];hi|=s[k+11];flags|=s[k+12];maxdelta=max(maxdelta,uintBitsToFloat(s[k+4]));}
 float u=5.960464477539063e-8;float eps=max(1e-7,q+max(1e-8,(8.0*u+2.0*(float(touched)+256.0)*u*u)*a));
 uint error=r[20];if(c[0]!=0x32535242u||c[1]!=2u||c[2]!=256u||c[21]!=p.n||c[62]!=0u||c[63]!=0u||c[23]>1u)error=5u;
 if((flags&256u)!=0u)error=16u;else if((flags&(1024u|4096u))!=0u)error=8u;else if((flags&512u)!=0u)error=17u;else if((flags&2048u)!=0u)error=16u;
 bool shovel=c[3]==3u;
 if(isnan(volume)||isinf(volume)||(!shovel&&volume<0.0))error=16u;
 if(shovel){
  if(isnan(removed)||isinf(removed)||isnan(left)||isinf(left)||isnan(right)||isinf(right)||abs(volume)>2.0*eps||abs(removed-left-right)>2.0*eps||abs(left-right)>2.0*eps)error=16u;
  if(removed>uintBitsToFloat(c[39])+eps)error=9u;
 }else if(volume>uintBitsToFloat(c[38])+eps)error=9u;
 r[20]=error;r[31]=flags;r[39]=shovel?c[39]:c[38];
 if(error!=0u){r[3]=3u;return;}
 if(count==0u){r[3]=2u;return;}
 r[3]=1u;r[14]=r[12]+1u;r[15]=r[13]+(r[14]==0u?1u:0u);
 r[22]=count;r[24]=minx;r[25]=minz;r[26]=maxx-minx+1u;r[27]=maxz-minz+1u;r[28]=lo;r[29]=hi;
 r[46]=floatBitsToUint(eps);r[51]=floatBitsToUint(maxdelta);
 if(shovel){r[32]=floatBitsToUint(left+right);r[33]=floatBitsToUint(removed);r[34]=r[33];r[35]=floatBitsToUint(left);r[36]=floatBitsToUint(right);r[45]=floatBitsToUint(volume);r[48]=floatBitsToUint(2.0*eps);r[50]=floatBitsToUint(uintBitsToFloat(s[4099])*0.015625);}
 else{r[32]=floatBitsToUint(volume);r[37]=r[32];r[49]=r[32];}
}
